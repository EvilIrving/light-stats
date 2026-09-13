//
//  WindowSnappingService.swift
//  Light Stats
//
//  Shared Accessibility-backed window positioning used by keyboard shortcuts and
//  titlebar trackpad gestures.
//

import AppKit
import ApplicationServices
import OSLog

/// Placement engine for window snapping.
///
/// macOS ships its own tiling — the items the system adds to every app's Window menu — and that
/// implementation always wins: it owns the per-display visible area, the animation, and the
/// behavior macOS already documents to users. This engine drives the items that match our actions,
/// and only places a window itself for what the system has no command for (thirds, display moves,
/// minimize) or when the native item is unavailable.
final class WindowSnappingService {

    /// What became of one placement attempt. Internal so tests can assert on the path taken.
    enum SnapOutcome {
        /// The window moved. The label names the path that produced it, for diagnostics.
        case moved(String)
        /// Nothing moved. The label is a stable reason code.
        case refused(String)

        var succeeded: Bool {
            switch self {
            case .moved: return true
            case .refused: return false
            }
        }

        var label: String {
            switch self {
            case .moved(let path): return path
            case .refused(let reason): return reason
            }
        }
    }

    /// Windows are remembered by their Accessibility element. `AXWindowNumber` would be the natural
    /// key but most apps never expose it (it reads as 0), and collapsing to (pid, title) makes two
    /// same-titled windows of one app share a single saved frame — which is how "restore" ends up
    /// resizing the wrong window.
    private struct WindowKey: Hashable {
        var processID: pid_t
        var element: AXUIElement

        static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
            lhs.processID == rhs.processID && CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(processID)
            hasher.combine(CFHash(element))
        }
    }

    private let logger = AppLogger(category: "WindowSnapping")
    private let nativeTiling = NativeWindowTilingService()
    private let targeting = WindowGestureTargeting()
    private let stateLock = NSLock()
    private var savedFrames: [WindowKey: CGRect] = [:]

    // MARK: - Entry points

    func checkPermission(promptIfNeeded: Bool) -> Bool {
        AccessibilityPermission.isTrusted(prompt: promptIfNeeded)
    }

    /// Snaps the frontmost app's focused window, as the global shortcuts do.
    func perform(_ action: WindowSnapAction) {
        recordRequest(action)
        guard checkPermission(promptIfNeeded: false) else {
            return recordResult(action, success: false, reason: "permission")
        }
        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let window = window(forApplication: processID) else {
            return recordResult(action, success: false, reason: "focusedWindow")
        }
        perform(action, on: window, processID: processID)
    }

    /// Snaps the window under a titlebar point, as the swipe gestures do.
    ///
    /// `zone` decides what counts as a valid start: the window's titlebar band (default) or simply
    /// the window under the pointer, which is the escape hatch for apps that draw their own titlebar.
    func perform(_ action: WindowSnapAction, at axPoint: CGPoint, zone: SnapGestureZone) {
        recordRequest(action, zone: zone)
        guard checkPermission(promptIfNeeded: false) else {
            return recordResult(action, success: false, reason: "permission")
        }

        let target = targeting.target(at: axPoint, zone: zone)
        if let rejection = target.rejection {
            return recordResult(action, success: false, reason: rejection)
        }
        guard let window = target.window, let processID = processIdentifier(of: window) else {
            return recordResult(action, success: false, reason: "noWindow")
        }
        perform(action, on: window, processID: processID)
    }

    /// Snaps a window of `processID`, as the menu bar icon does.
    ///
    /// Opening our own status item menu already took frontmost status away from the app the user
    /// was working in, so the caller passes the app it saw before the menu opened; frontmost status
    /// is handed back before anything native runs.
    func perform(_ action: WindowSnapAction, forApplication processID: pid_t) {
        recordRequest(action)
        guard checkPermission(promptIfNeeded: false) else {
            return recordResult(action, success: false, reason: "permission")
        }
        guard let window = window(forApplication: processID) else {
            return recordResult(action, success: false, reason: "focusedWindow")
        }
        _ = nativeTiling.activate(processID)
        perform(action, on: window, processID: processID)
    }

    func canPerform(_ action: WindowSnapAction) -> Bool {
        guard checkPermission(promptIfNeeded: false),
              let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        return canPerform(action, forApplication: processID)
    }

    func canPerform(_ action: WindowSnapAction, forApplication processID: pid_t) -> Bool {
        guard checkPermission(promptIfNeeded: false),
              let window = window(forApplication: processID) else { return false }
        return canPerform(action, on: window, processID: processID)
    }

    func previewFrame(for action: WindowSnapAction, at axPoint: CGPoint, zone: SnapGestureZone) -> CGRect? {
        guard checkPermission(promptIfNeeded: false) else { return nil }
        let target = targeting.target(at: axPoint, zone: zone)
        guard let window = target.window, target.rejection == nil else { return nil }
        return previewFrame(for: action, on: window)
    }

    /// Why a gesture may not start here, or `nil` when it may.
    ///
    /// The gesture engine asks before it shows anything, so a swipe that begins on a control never
    /// previews and never fires the threshold haptic — the app's own reaction to that swipe is left
    /// alone instead of being doubled up with a snap.
    func gestureRejection(at axPoint: CGPoint, zone: SnapGestureZone) -> String? {
        guard checkPermission(promptIfNeeded: false) else { return "permission" }
        return targeting.target(at: axPoint, zone: zone).rejection
    }

    // MARK: - Placement

    private func perform(_ action: WindowSnapAction, on window: AXUIElement, processID: pid_t) {
        guard canPerform(action, on: window, processID: processID) else {
            return recordResult(action, success: false, reason: "unavailable")
        }

        let outcome = place(action, on: window, processID: processID)
        recordResult(action, success: outcome.succeeded, reason: outcome.label, window: window)
        if outcome.succeeded {
            performHapticFeedback()
        }
    }

    private func place(_ action: WindowSnapAction, on window: AXUIElement, processID: pid_t) -> SnapOutcome {
        if let command = NativeTilingCommand.matching(action),
           performNatively(command, action: action, on: window, processID: processID) {
            return .moved("native")
        }
        return placeLocally(action, on: window)
    }

    private func canPerform(_ action: WindowSnapAction, on window: AXUIElement, processID: pid_t) -> Bool {
        // A minimized window cannot be placed, and the system's own tiling items are disabled for
        // one too, so the menu item stays honest instead of offering a no-op.
        guard isFullScreen(window) != true, isMinimized(window) != true else { return false }

        if let command = NativeTilingCommand.matching(action), nativeTiling.supports(command, processID: processID) {
            return true
        }

        switch action {
        case .restore:
            return savedFrame(for: window) != nil
        case .minimize:
            return isMinimized(window) != true
        case .nextDisplay, .previousDisplay:
            return NSScreen.screens.count > 1 && frame(of: window) != nil
        default:
            return canPlace(window)
        }
    }

    /// The window is movable at all. Which target it already sits on is deliberately not part of
    /// this: a window that is already in the requested half keeps its menu item enabled and the
    /// press is a no-op, exactly like the system's own tiling items.
    private func canPlace(_ window: AXUIElement) -> Bool {
        guard frame(of: window) != nil else { return false }
        return isSettable(kAXPositionAttribute, of: window) || isSettable(kAXSizeAttribute, of: window)
    }

    /// Placing a window directly, without going through the system's tiling.
    ///
    /// Internal rather than private so tests can drive it against a real window; that is the only
    /// way to prove a frame write actually lands, which is exactly what used to fail silently.
    func placeLocally(_ action: WindowSnapAction, on window: AXUIElement) -> SnapOutcome {
        switch action {
        case .restore:
            return restore(window)
        case .minimize:
            return minimize(window)
        case .nextDisplay:
            return moveToAdjacentDisplay(window, direction: 1)
        case .previousDisplay:
            return moveToAdjacentDisplay(window, direction: -1)
        default:
            return snap(window, action: action)
        }
    }

    private func snap(_ window: AXUIElement, action: WindowSnapAction) -> SnapOutcome {
        guard let currentFrame = frame(of: window),
              let targetFrame = targetFrame(for: action, on: window) else {
            return .refused("target")
        }

        saveFrameIfNeeded(currentFrame, for: window)
        guard let achieved = apply(targetFrame, to: window) else { return .refused("setFrame") }
        if WindowSnapGeometry.framesApproximatelyEqual(achieved, targetFrame) {
            return .moved("local")
        }
        if WindowSnapGeometry.framesApproximatelyEqual(achieved, currentFrame, tolerance: 1) {
            return .refused("unmoved")
        }
        logger.debug("Window accepted a clamped frame \(achieved) for target \(targetFrame)")
        return .moved("localClamped")
    }

    private func minimize(_ window: AXUIElement) -> SnapOutcome {
        let minimized = kCFBooleanTrue as CFTypeRef
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized)
        return result == .success ? .moved("local") : .refused("minimize")
    }

    private func restore(_ window: AXUIElement) -> SnapOutcome {
        guard let key = windowKey(for: window), let savedFrame = savedFrames[key] else {
            return .refused("noSavedFrame")
        }
        guard let achieved = apply(savedFrame, to: window) else { return .refused("setFrame") }
        removeSavedFrame(for: key)
        guard WindowSnapGeometry.framesApproximatelyEqual(achieved, savedFrame) else {
            return .refused("unmoved")
        }
        return .moved("local")
    }

    private func moveToAdjacentDisplay(_ window: AXUIElement, direction: Int) -> SnapOutcome {
        guard let currentFrame = frame(of: window),
              let currentScreen = screen(containingAXFrame: currentFrame) else {
            return .refused("display")
        }

        let screens = orderedScreens()
        guard screens.count > 1, let currentIndex = screens.firstIndex(of: currentScreen) else {
            return .refused("display")
        }

        let targetIndex = (currentIndex + direction + screens.count) % screens.count
        let targetFrame = WindowSnapGeometry.transferredFrame(
            currentFrame,
            from: axRect(fromCocoaRect: currentScreen.visibleFrame),
            to: axRect(fromCocoaRect: screens[targetIndex].visibleFrame)
        )

        saveFrameIfNeeded(currentFrame, for: window)
        guard let achieved = apply(targetFrame, to: window) else { return .refused("setFrame") }
        guard !WindowSnapGeometry.framesApproximatelyEqual(achieved, currentFrame, tolerance: 1) else {
            return .refused("unmoved")
        }
        return .moved("local")
    }

    // MARK: - Native tiling

    /// Hands the action to the system and lets it place the window.
    ///
    /// macOS animates the move by actually moving the window, so its frame is still the old one when
    /// the press returns; whether the system honoured the command can only be answered once the
    /// animation settles, which is what `confirmNativePlacement` does asynchronously.
    private func performNatively(
        _ command: NativeTilingCommand,
        action: WindowSnapAction,
        on window: AXUIElement,
        processID: pid_t
    ) -> Bool {
        guard let before = frame(of: window), nativeTiling.perform(command, processID: processID) else {
            return false
        }
        confirmNativePlacement(action, window: window, before: before)
        return true
    }

    /// A press is accepted even when the item is disabled, and the system then does nothing. If the
    /// window is still where it was once the animation is over, the engine places it itself.
    private func confirmNativePlacement(_ action: WindowSnapAction, window: AXUIElement, before: CGRect) {
        Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, let after = self.frame(of: window) else { return }
            guard WindowSnapGeometry.framesApproximatelyEqual(after, before, tolerance: 1) else { return }

            self.logger.debug("Native tiling left the window in place; placing it directly")
            let outcome = self.placeLocally(action, on: window)
            self.recordResult(action, success: outcome.succeeded, reason: "native-\(outcome.label)", window: window)
        }
    }

    // MARK: - Target resolution

    private func window(forApplication processID: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processID)
        if let focused: AXUIElement = AXElementReader.attribute(kAXFocusedWindowAttribute, from: application) {
            return focused
        }
        if let main: AXUIElement = AXElementReader.attribute(kAXMainWindowAttribute, from: application) {
            return main
        }
        // The menu bar icon acts on an app that is not frontmost, where neither of the above is
        // guaranteed to resolve.
        let windows = AXElementReader.elements(kAXWindowsAttribute, from: application)
        return windows.first { isMinimized($0) != true } ?? windows.first
    }

    // MARK: - Geometry

    /// Frame `action` asks for on the screen holding `window`, in Accessibility space. Internal for
    /// tests, which assert the placed frame against the same computation the engine uses.
    func targetFrame(for action: WindowSnapAction, on window: AXUIElement) -> CGRect? {
        guard let currentFrame = frame(of: window),
              let screen = screen(containingAXFrame: currentFrame) else { return nil }
        let visibleFrame = axRect(fromCocoaRect: screen.visibleFrame)

        if action == .center {
            let size = savedFrame(for: window)?.size ?? currentFrame.size
            return WindowSnapGeometry.centeredFrame(size: size, in: visibleFrame)
        }
        if action == .minimize {
            return WindowSnapGeometry.minimizePreviewFrame(in: visibleFrame)
        }
        return WindowSnapGeometry.targetFrame(
            for: action,
            visibleFrame: visibleFrame,
            currentSize: currentFrame.size
        )
    }

    private func previewFrame(for action: WindowSnapAction, on window: AXUIElement) -> CGRect? {
        guard let targetFrame = targetFrame(for: action, on: window) else { return nil }
        return cocoaRect(fromAXRect: targetFrame)
    }

    private func screen(containingAXFrame frame: CGRect) -> NSScreen? {
        let cocoaFrame = cocoaRect(fromAXRect: frame)
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        if let containing = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return containing
        }

        // A window straddling two displays has its center on neither; the one under most of it wins.
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(cocoaFrame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }
        return bestScreen ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Screens ordered top-to-bottom, then left-to-right, in Accessibility space — so "next
    /// display" means the same thing on a vertical stack as on a horizontal row.
    private func orderedScreens() -> [NSScreen] {
        NSScreen.screens.sorted { lhs, rhs in
            let left = axRect(fromCocoaRect: lhs.frame)
            let right = axRect(fromCocoaRect: rhs.frame)
            if abs(left.minY - right.minY) > 1 { return left.minY < right.minY }
            return left.minX < right.minX
        }
    }

    /// Reference height for the Accessibility ↔ Cocoa flip: the primary display, the one sitting at
    /// the Cocoa origin and holding the menu bar.
    ///
    /// Using the highest `maxY` across all displays instead shifts every frame by the height of
    /// whatever sits above the primary one, which is why snapping used to break as soon as an
    /// external display was arranged above the built-in one.
    private func flipReferenceMaxY() -> CGFloat {
        let primary = NSScreen.screens.first { $0.frame.contains(CGPoint.zero) } ?? NSScreen.screens.first
        return primary?.frame.maxY ?? 0
    }

    private func axRect(fromCocoaRect rect: CGRect) -> CGRect {
        WindowSnapGeometry.flip(rect, aboutMaxY: flipReferenceMaxY())
    }

    private func cocoaRect(fromAXRect rect: CGRect) -> CGRect {
        WindowSnapGeometry.flip(rect, aboutMaxY: flipReferenceMaxY())
    }

    // MARK: - Window attributes

    /// Frame a window currently reports, in Accessibility space. Internal for tests.
    func frame(of window: AXUIElement) -> CGRect? {
        AXElementReader.frame(of: window)
    }

    /// Writes a frame and reports what the window actually ended up with.
    ///
    /// Size is written first and the pair twice: an app that re-clamps its origin after a resize —
    /// which is most of them — otherwise leaves the window at the right size in the wrong place.
    /// A window that cannot be resized still gets its position moved.
    private func apply(_ frame: CGRect, to window: AXUIElement) -> CGRect? {
        let resizable = isSettable(kAXSizeAttribute, of: window)
        let movable = isSettable(kAXPositionAttribute, of: window)
        guard resizable || movable else { return nil }

        if resizable {
            _ = setSize(frame.size, for: window)
        }
        if movable {
            _ = setPosition(frame.origin, for: window)
        }
        if resizable {
            _ = setSize(frame.size, for: window)
        }
        if movable {
            _ = setPosition(frame.origin, for: window)
        }
        return self.frame(of: window)
    }

    private func setPosition(_ position: CGPoint, for window: AXUIElement) -> Bool {
        var mutablePosition = position
        guard let value = AXValueCreate(.cgPoint, &mutablePosition) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private func setSize(_ size: CGSize, for window: AXUIElement) -> Bool {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    private func isFullScreen(_ window: AXUIElement) -> Bool? {
        AXElementReader.attribute(fullScreenAttribute, from: window)
    }

    private func isMinimized(_ window: AXUIElement) -> Bool? {
        AXElementReader.attribute(kAXMinimizedAttribute, from: window)
    }

    private func isSettable(_ attribute: String, of window: AXUIElement) -> Bool {
        AXElementReader.isSettable(attribute, of: window)
    }

    private func processIdentifier(of window: AXUIElement) -> pid_t? {
        AXElementReader.processIdentifier(of: window)
    }

    private var fullScreenAttribute: String { "AXFullScreen" }

    // MARK: - Saved frames

    private func windowKey(for window: AXUIElement) -> WindowKey? {
        guard let processID = AXElementReader.processIdentifier(of: window) else { return nil }
        return WindowKey(processID: processID, element: window)
    }

    private func savedFrame(for window: AXUIElement) -> CGRect? {
        guard let key = windowKey(for: window) else { return nil }
        stateLock.lock()
        defer { stateLock.unlock() }
        return savedFrames[key]
    }

    private func saveFrameIfNeeded(_ frame: CGRect, for window: AXUIElement) {
        guard let key = windowKey(for: window) else { return }
        stateLock.lock()
        defer { stateLock.unlock() }
        if savedFrames[key] == nil {
            savedFrames[key] = frame
        }
    }

    private func removeSavedFrame(for key: WindowKey) {
        stateLock.lock()
        savedFrames[key] = nil
        stateLock.unlock()
    }

    // MARK: - Diagnostics and feedback

    private func recordRequest(_ action: WindowSnapAction, zone: SnapGestureZone? = nil) {
        var fields = ["snapAction": String(describing: action)]
        if let zone {
            fields["zone"] = zone.diagnosticName
        }
        DiagnosticLogService.record(
            category: "windowManagement",
            action: "requested",
            fields: fields
        )
    }

    /// Failures carry the layout evidence needed to explain them: which screen the engine believed
    /// it was on, what the flip reference was, and where the window actually sat. Without these a
    /// refused snap is indistinguishable from a rejected one after the fact.
    private func recordResult(_ action: WindowSnapAction, success: Bool, reason: String = "", window: AXUIElement? = nil) {
        var fields = ["snapAction": String(describing: action), "reason": reason]
        if !success {
            fields["screens"] = String(NSScreen.screens.count)
            fields["primaryMaxY"] = String(format: "%.0f", flipReferenceMaxY())
            if let window, let frame = frame(of: window) {
                fields["windowFrame"] = describe(frame)
                fields["windowScreen"] = describe(axRect(fromCocoaRect: screen(containingAXFrame: frame)?.frame ?? .zero))
            }
        }

        DiagnosticLogService.record(
            level: success ? .info : .error,
            category: "windowManagement",
            action: success ? "succeeded" : "failed",
            fields: fields
        )
    }

    private func describe(_ rect: CGRect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", rect.minX, rect.minY, rect.width, rect.height)
    }

    private func performHapticFeedback() {
        Task { @MainActor in
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
