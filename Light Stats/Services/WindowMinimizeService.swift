//
//  WindowMinimizeService.swift
//  Light Stats
//

import AppKit
import ApplicationServices

/// Minimizing and restoring another application's windows.
///
/// Separate from `WindowVisibilityService` on purpose: that one hides whole applications and is
/// reversible with one call, while minimizing is per window, may be refused by the window itself,
/// and has to be confirmed by reading the attribute back. The two also differ in what the user
/// sees — a hidden app leaves no trace, a minimized window lands in the Dock.
///
/// The write is attempted in the order that survives real windows: set `AXMinimized`, and when the
/// window refuses it, press the window's own minimize
/// button; then retry the whole thing once, because the first attempt regularly lands while the
/// window is still animating and is silently dropped.
nonisolated final class WindowMinimizeService: @unchecked Sendable {

    /// What a click is judged on. All of it read from Accessibility, none of it cached: the Dock
    /// changes the window list between clicks, and a stale answer collapses the wrong window set.
    struct WindowFacts: Sendable {
        var hasVisibleWindows: Bool
        var hasCollapsibleWindows: Bool
        var hasMinimizedWindows: Bool
        var focusedTitle: String?
    }

    struct Outcome: Sendable {
        var processID: pid_t
        var changed: Int
        var attempted: Int
        var reason: String

        var succeeded: Bool { changed > 0 && changed == attempted }
    }

    /// The windows this service put away, per application.
    ///
    /// Remembered by title rather than by `AXUIElement` because a minimized window's element is not
    /// stable across Dock animations, and by `ProcessIdentity` because a pid alone can be reused by a
    /// different application between the click and the click-back.
    struct CollapseRecord: Sendable {
        var identity: ProcessIdentity?
        var titles: [String]
        var focusedTitle: String?
    }

    /// Window roles that may be minimized. A sheet, a popover, or a dialog is not a window the user
    /// thinks of as "this app's windows", and minimizing one is how a click turns into a surprise.
    private static let collapsibleSubroles: Set<String> = ["AXStandardWindow"]
    /// How many applications' collapsed sets to remember. A Dock has at most a few dozen icons; the
    /// cap only exists so a long session cannot grow the bookkeeping without bound.
    private static let recordLimit = 16
    /// Pause between the two waves.
    ///
    /// The read-back right after a write is not the truth: a window that is mid-animation accepts
    /// `AXMinimized` and keeps reporting the old value, which is exactly why the reference
    /// implementation runs a second wave instead of trusting one pass. Waiting lets the first write
    /// commit before the second wave decides who still needs help.
    private static let retryDelay: useconds_t = 90_000

    private let stateLock = NSLock()
    private var records: [pid_t: CollapseRecord] = [:]

    // MARK: - Reading

    /// Window facts for the click decision. Runs on the AX queue.
    func windowFacts(processID: pid_t) -> WindowFacts {
        let windows = standardWindows(processID: processID)
        let focused = windows.first { (attribute("AXFocused", from: $0) as Bool?) == true }
        var hasVisible = false
        var hasCollapsible = false
        var hasMinimized = false
        for window in windows {
            let isMinimized = (attribute(kAXMinimizedAttribute, from: window) as Bool?) ?? false
            let isFullScreen = (attribute("AXFullScreen", from: window) as Bool?) ?? false
            if isMinimized { hasMinimized = true }
            if !isMinimized { hasVisible = true }
            if !isMinimized, !isFullScreen { hasCollapsible = true }
        }
        return WindowFacts(
            hasVisibleWindows: hasVisible,
            hasCollapsibleWindows: hasCollapsible,
            hasMinimizedWindows: hasMinimized,
            focusedTitle: focused.flatMap { attribute(kAXTitleAttribute, from: $0) as String? }
        )
    }

    /// Whether this application's windows are the set this service put away — the question the click
    /// decision asks before it restores instead of collapsing again.
    func recordExists(for processID: pid_t) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return records[processID] != nil
    }

    func forget(processID: pid_t) {
        stateLock.lock()
        records[processID] = nil
        stateLock.unlock()
    }

    /// Drops all bookkeeping. Called when the feature is switched off: the windows stay minimized —
    /// putting them back would be a side effect nobody asked for — but a later click can no longer
    /// claim to be restoring them.
    func forgetAll() {
        stateLock.lock()
        records.removeAll()
        stateLock.unlock()
    }

    // MARK: - Minimizing

    /// Minimizes every collapsible window of `processID`, remembering the set for the next click.
    /// Runs on the AX queue.
    ///
    /// Two waves, and the verdict comes from what the Accessibility calls *accepted* rather than from
    /// a single read-back: an accepted write is the OS's answer that the window is being minimized,
    /// and a window that is mid-animation legitimately still reports the old value for a moment.
    func collapse(processID: pid_t, facts: WindowFacts) -> Outcome {
        let windows = standardWindows(processID: processID).filter { window in
            !isMinimized(window) && !isFullScreen(window)
        }
        guard !windows.isEmpty else {
            return Outcome(processID: processID, changed: 0, attempted: 0, reason: "no-collapsible-window")
        }

        var minimized = Set<Int>()
        for (index, window) in windows.enumerated() where setMinimized(window, true) {
            minimized.insert(index)
        }

        usleep(Self.retryDelay)
        for (index, window) in windows.enumerated() where !minimized.contains(index) || !isMinimized(window) {
            if setMinimized(window, true) {
                minimized.insert(index)
            } else if pressMinimizeButton(window) {
                minimized.insert(index)
            }
        }

        let titles = minimized.sorted().compactMap { index in
            attribute(kAXTitleAttribute, from: windows[index]) as String?
        }
        remember(
            CollapseRecord(
                identity: ProcessIdentityReader.read(processID),
                titles: titles,
                focusedTitle: facts.focusedTitle
            ),
            for: processID
        )

        let attempted = windows.count
        let changed = minimized.count
        let reason = changed == attempted ? "confirmed" : (changed > 0 ? "partial" : "refused")
        return Outcome(processID: processID, changed: changed, attempted: attempted, reason: reason)
    }

    // MARK: - Restoring

    /// Brings back the windows this service minimized for `processID`, and focuses the one that had
    /// focus before. Runs on the AX queue. Reports `no-record` when there is nothing to undo, which is
    /// how a click after the user closed those windows stops pretending to restore anything.
    func restore(processID: pid_t) -> Outcome {
        stateLock.lock()
        let record = records.removeValue(forKey: processID)
        stateLock.unlock()
        guard let record else {
            return Outcome(processID: processID, changed: 0, attempted: 0, reason: "no-record")
        }
        guard record.identity == nil || ProcessIdentityReader.read(processID) == record.identity else {
            return Outcome(processID: processID, changed: 0, attempted: 0, reason: "process-changed")
        }

        let wanted = Set(record.titles)
        let windows = standardWindows(processID: processID).filter { window in
            guard let title = attribute(kAXTitleAttribute, from: window) as String? else { return true }
            return wanted.contains(title)
        }
        guard !windows.isEmpty else {
            return Outcome(processID: processID, changed: 0, attempted: 0, reason: "windows-gone")
        }

        var changed = 0
        var focused: AXUIElement?
        for window in windows where isMinimized(window) {
            guard setMinimized(window, false) else { continue }
            changed += 1
            if (attribute(kAXTitleAttribute, from: window) as String?) == record.focusedTitle { focused = window }
        }
        if focused == nil {
            focused = windows.first { !isMinimized($0) }
        }
        if let focused {
            AXUIElementPerformAction(focused, kAXRaiseAction as CFString)
        }
        // Activating is what makes the restored window usable: a minimized window comes back *behind*
        // whatever the user is now looking at.
        NSRunningApplication(processIdentifier: processID)?.activate()
        return Outcome(processID: processID, changed: changed, attempted: windows.count, reason: changed > 0 ? "confirmed" : "refused")
    }

    // MARK: - Accessibility plumbing

    private func standardWindows(processID: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.08)
        return AXElementReader.elements(kAXWindowsAttribute, from: application).filter { window in
            let subrole = attribute(kAXSubroleAttribute, from: window) as String?
            return subrole.map { Self.collapsibleSubroles.contains($0) } ?? false
        }
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        (attribute(kAXMinimizedAttribute, from: window) as Bool?) ?? false
    }

    private func isFullScreen(_ window: AXUIElement) -> Bool {
        (attribute("AXFullScreen", from: window) as Bool?) ?? false
    }

    /// Whether the write was accepted. This — not a read-back — is the outcome of one attempt: the
    /// window itself knows its animation is not finished.
    @discardableResult
    private func setMinimized(_ window: AXUIElement, _ minimized: Bool) -> Bool {
        let value: CFTypeRef = minimized ? (kCFBooleanTrue as CFTypeRef) : (kCFBooleanFalse as CFTypeRef)
        return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value) == .success
    }

    /// The fallback for a window that refuses the attribute: press its own minimize button.
    private func pressMinimizeButton(_ window: AXUIElement) -> Bool {
        guard let button = minimizeButton(of: window) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// The window's own minimize button.
    ///
    /// Both routes are needed: AppKit exposes the button as the private `AXMinimizeButton` attribute,
    /// while Electron and Java windows only expose it as a child with the minimize subrole.
    private func minimizeButton(of window: AXUIElement) -> AXUIElement? {
        if let button: AXUIElement = attribute("AXMinimizeButton", from: window) { return button }
        return AXElementReader.elements(kAXChildrenAttribute, from: window).first { child in
            (attribute(kAXSubroleAttribute, from: child) as String?) == "AXMinimizeButton"
        }
    }

    private func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        AXElementReader.attribute(name, from: element)
    }

    private func remember(_ record: CollapseRecord, for processID: pid_t) {
        stateLock.lock()
        if records.count >= Self.recordLimit, records[processID] == nil {
            records.removeValue(forKey: records.keys.first ?? processID)
        }
        records[processID] = record
        stateLock.unlock()
    }
}
