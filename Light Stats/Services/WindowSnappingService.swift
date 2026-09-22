//
//  WindowSnappingService.swift
//  Light Stats
//
//  Shared Accessibility-backed window positioning used by keyboard shortcuts, the menu bar icon,
//  titlebar gestures, and the drag-to-edge pipeline.
//

import AppKit
import ApplicationServices
import OSLog

/// Orchestrates window placement.
///
/// Responsibilities, in order of importance:
///
/// 1. **Decide what to act on.** Resolving and filtering the target window is where a window
///    manager earns or loses trust; see `WindowSnapEligibility`.
/// 2. **Keep an honest restore point** for every window it touches, on every path.
/// 3. **Delegate the actual move** to `WindowPlacementEngine`, or to the system's own tiling item
///    when the user has asked for that.
///
/// It deliberately does not compute geometry. That lives in `WindowSnapGeometry`,
/// `SnapGridGeometry`, and `WindowPlacementEngine.resolvedFrame`, so the preview overlay, the
/// island, and the engine all read the same numbers.
nonisolated final class WindowSnappingService: @unchecked Sendable {

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
    private let engine = WindowPlacementEngine()
    private let nativeTiling = NativeWindowTilingService()
    private let visibility = WindowVisibilityService()
    private let targeting = WindowGestureTargeting()
    private let stateLock = NSLock()

    private var configuration: SnapConfiguration = .default
    private var history = WindowSnapHistory<WindowKey>()
    private var placementRevision: UInt64 = 0

    // MARK: - Configuration

    /// The service is not `@MainActor` (the drag pipeline calls it from its own thread), so the
    /// configuration is stored under the same lock as the history rather than being read live from
    /// `SettingsManager`, which lives in the ViewModels layer and may only be touched on main.
    func update(configuration: SnapConfiguration) {
        stateLock.lock()
        self.configuration = configuration
        placementRevision &+= 1
        stateLock.unlock()
    }

    func currentConfiguration() -> SnapConfiguration {
        stateLock.lock()
        defer { stateLock.unlock() }
        return configuration
    }

    func checkPermission(promptIfNeeded: Bool) -> Bool {
        AccessibilityPermission.isTrusted(prompt: promptIfNeeded)
    }

    /// Forgets every restore point — used when window management is switched off, so a stale
    /// rectangle cannot be applied after the user re-enables it much later.
    func resetHistory() {
        stateLock.lock()
        history.removeAll()
        placementRevision &+= 1
        stateLock.unlock()
    }

    // MARK: - Entry points

    /// Snaps the frontmost app's focused window, as the global shortcuts do.
    func perform(_ action: WindowSnapAction) {
        perform(.action(action))
    }

    func perform(_ target: SnapTarget) {
        recordRequest(target)
        if case .visibility(let command) = target {
            return performVisibility(command, keeping: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        }
        if let action = target.action, action.isWindowControl,
           let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            return recordResult(target, success: WindowControlService.perform(action, processID: processID), reason: action.rawValue)
        }
        guard checkPermission(promptIfNeeded: false) else {
            return recordResult(target, success: false, reason: "permission")
        }
        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let window = focusedWindow(forApplication: processID) else {
            return recordResult(target, success: false, reason: "focusedWindow")
        }
        perform(target, on: window, processID: processID)
    }

    /// Snaps a window of `processID`, as the menu bar icon does.
    ///
    /// Opening our own status item menu already took frontmost status away from the app the user
    /// was working in, so the caller passes the app it saw before the menu opened; frontmost status
    /// is handed back before anything native runs.
    func perform(_ action: WindowSnapAction, forApplication processID: pid_t) {
        perform(.action(action), forApplication: processID)
    }

    func perform(_ target: SnapTarget, forApplication processID: pid_t) {
        recordRequest(target)
        if let action = target.action, action.isWindowControl {
            return recordResult(target, success: WindowControlService.perform(action, processID: processID), reason: action.rawValue)
        }
        guard checkPermission(promptIfNeeded: false) else {
            return recordResult(target, success: false, reason: "permission")
        }
        guard let window = focusedWindow(forApplication: processID) else {
            return recordResult(target, success: false, reason: "focusedWindow")
        }
        _ = nativeTiling.activate(processID)
        perform(target, on: window, processID: processID)
    }

    /// Snaps the window under a titlebar point, as the swipe gestures do.
    ///
    /// `zone` decides what counts as a valid start: the window's titlebar band (default) or simply
    /// the window under the pointer, which is the escape hatch for apps that draw their own titlebar.
    func perform(_ action: WindowSnapAction, at axPoint: CGPoint, zone: SnapGestureZone) {
        recordRequest(.action(action), zone: zone)
        guard checkPermission(promptIfNeeded: false) else {
            return recordResult(.action(action), success: false, reason: "permission")
        }

        let target = targeting.target(at: axPoint, zone: zone)
        if let rejection = target.rejection {
            return recordResult(.action(action), success: false, reason: rejection)
        }
        guard let window = target.window, let processID = processIdentifier(of: window) else {
            return recordResult(.action(action), success: false, reason: "noWindow")
        }
        perform(.action(action), on: window, processID: processID)
    }

    /// Places a window the caller has already resolved — the drag pipeline's commit path.
    func perform(_ target: SnapTarget, on window: AXUIElement, processID: pid_t, screen: SnapScreenGeometry? = nil) {
        AXCommandQueue.shared.async { [weak self] in
            self?.performOnQueue(target, on: window, processID: processID, screen: screen)
        }
    }

    private func performOnQueue(_ target: SnapTarget, on window: AXUIElement, processID: pid_t, screen: SnapScreenGeometry?) {
        recordRequest(target)
        if let action = target.action, action.isWindowControl {
            return recordResult(target, success: WindowControlService.perform(action, processID: processID), reason: action.rawValue)
        }
        guard checkPermission(promptIfNeeded: false) else {
            return recordResult(target, success: false, reason: "permission")
        }
        guard let rejection = rejection(for: window, processID: processID) else {
            return place(target, on: window, processID: processID, screen: screen)
        }
        recordResult(target, success: false, reason: rejection)
    }

    // MARK: - Queries

    func canPerform(_ action: WindowSnapAction) -> Bool {
        canPerform(.action(action))
    }

    func canPerform(_ target: SnapTarget) -> Bool {
        if case .visibility(let command) = target {
            // `restore` with nothing hidden would be a no-op, so its menu item stays disabled.
            return !command.requiresHiddenApplications || visibility.hiddenCount > 0
        }
        guard checkPermission(promptIfNeeded: false),
              let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        return canPerform(target, forApplication: processID)
    }

    func canPerform(_ action: WindowSnapAction, forApplication processID: pid_t) -> Bool {
        canPerform(.action(action), forApplication: processID)
    }

    func canPerform(_ target: SnapTarget, forApplication processID: pid_t) -> Bool {
        if let action = target.action, action.isWindowControl {
            return WindowControlService.canPerform(action, processID: processID)
        }
        if case .visibility(let command) = target {
            return !command.requiresHiddenApplications || visibility.hiddenCount > 0
        }
        guard checkPermission(promptIfNeeded: false),
              let window = focusedWindow(forApplication: processID),
              rejection(for: window, processID: processID) == nil else { return false }
        return canPlace(target, on: window, processID: processID)
    }

    /// Frame a target will produce for a window, in Cocoa space, for the swipe gesture's preview.
    func previewFrame(for action: WindowSnapAction, at axPoint: CGPoint, zone: SnapGestureZone) -> CGRect? {
        guard checkPermission(promptIfNeeded: false) else { return nil }
        let gestureTarget = targeting.target(at: axPoint, zone: zone)
        guard let window = gestureTarget.window, gestureTarget.rejection == nil else { return nil }
        return previewFrame(for: .action(action), on: window)
    }

    func previewFrame(for target: SnapTarget, on window: AXUIElement) -> CGRect? {
        guard let current = WindowFrameResolver.frame(of: window)?.frame,
              let screen = ScreenGeometryProvider.screen(containing: current),
              let frame = WindowPlacementEngine.resolvedFrame(
                  for: target,
                  screen: screen,
                  currentSize: current.size,
                  preferredSize: preferredSize(for: window)
              ) else { return nil }
        return ScreenGeometryProvider.toCocoa(frame)
    }

    /// Frame a target will produce on a specific display, for the drag pipeline — which knows the
    /// display from the pointer and must not guess it from the window.
    func previewFrame(for target: SnapTarget, screen: SnapScreenGeometry, currentSize: CGSize) -> CGRect? {
        WindowPlacementEngine.resolvedFrame(
            for: target,
            screen: screen,
            currentSize: currentSize
        )
    }

    /// Why a gesture may not start here, or `nil` when it may.
    ///
    /// The gesture engine asks before it shows anything, so a swipe that begins on a control never
    /// previews and never fires the threshold haptic — the app's own reaction to that swipe is left
    /// alone instead of being doubled up with a snap.
    func gestureRejection(at axPoint: CGPoint, zone: SnapGestureZone) -> String? {
        guard checkPermission(promptIfNeeded: false) else { return "permission" }
        let target = targeting.target(at: axPoint, zone: zone)
        if let rejection = target.rejection { return rejection }
        guard let window = target.window, let processID = processIdentifier(of: window) else { return "noWindow" }
        return rejection(for: window, processID: processID)
    }

    /// Why this window may not be manipulated, or `nil` when it may.
    ///
    /// Also used by the drag pipeline, which has to decide once per drag whether the window under
    /// the pointer is a real window and not, say, a Chrome toolbar flyout.
    func rejection(for window: AXUIElement, processID: pid_t) -> String? {
        let configuration = currentConfiguration()
        return SnapWindowEligibility.rejection(
            for: candidate(for: window, processID: processID),
            userExclusions: configuration.exclusionSet,
            honorsRestrictedList: configuration.honorsRestrictedApps
        )
    }

    func candidate(for window: AXUIElement, processID: pid_t) -> SnapWindowCandidate {
        let application = NSRunningApplication(processIdentifier: processID)
        return SnapWindowCandidate(
            role: AXElementReader.attribute(kAXRoleAttribute, from: window),
            subrole: AXElementReader.attribute(kAXSubroleAttribute, from: window),
            title: AXElementReader.attribute(kAXTitleAttribute, from: window),
            bundleIdentifier: application?.bundleIdentifier,
            executableName: application?.executableURL?.lastPathComponent,
            frame: WindowFrameResolver.frame(of: window)?.frame,
            isMinimized: isMinimized(window) == true,
            isFullScreen: isFullScreen(window) == true
        )
    }

    /// Hides or restores applications. No Accessibility permission, no window, no geometry.
    func performVisibility(_ command: WindowVisibilityCommand, keeping processID: pid_t?) {
        let performed: Bool
        switch command {
        case .hideOthers:
            performed = visibility.hideOthers(keeping: processID) >= 0
        case .hideAll:
            performed = visibility.hideAll() >= 0
        case .restore:
            performed = visibility.restore() >= 0
        }
        recordResult(.visibility(command), success: performed, reason: command.rawValue)
        if performed {
            performHapticFeedback()
        }
    }

    /// Forgets which applications were hidden without bringing them back — used when window
    /// management is switched off.
    func forgetHiddenApplications() {
        visibility.forgetHistory()
    }

    /// Size the window had before it was snapped, exposed so `.center` can restore it rather than
    /// centring a window at whatever size the previous snap left it.
    func preferredSize(for window: AXUIElement) -> CGSize? {
        guard let key = windowKey(for: window) else { return nil }
        stateLock.lock()
        defer { stateLock.unlock() }
        return history.record(for: key)?.original.size
    }

    // MARK: - Placement

    private func place(_ target: SnapTarget, on window: AXUIElement, processID: pid_t, screen: SnapScreenGeometry?) {
        stateLock.lock()
        placementRevision &+= 1
        stateLock.unlock()
        guard canPlace(target, on: window, processID: processID) else {
            return recordResult(target, success: false, reason: "unavailable", window: window)
        }

        let configuration = currentConfiguration()
        let record = windowKey(for: window).flatMap { key -> CGRect? in
            stateLock.lock()
            defer { stateLock.unlock() }
            return history.record(for: key)?.original
        }

        // The restore point is taken **before either path runs**. The previous implementation only
        // recorded it inside the local placement function, so every snap that the system's tiling
        // item handled returned early and left the window unrestorable.
        if case .action(.restore) = target {
            // Restoring consumes the record; preparing it here would immediately re-seed it.
        } else if let key = windowKey(for: window), let current = WindowFrameResolver.frame(of: window)?.frame {
            stateLock.lock()
            history.prepare(key: key, currentFrame: current)
            stateLock.unlock()
        }

        let outcome: WindowPlacementEngine.Outcome
        if case .action(.restore) = target {
            outcome = restore(window)
        } else if let command = nativeCommand(for: target, configuration: configuration) {
            outcome = placeNatively(
                command,
                target: target,
                on: window,
                processID: processID,
                configuration: configuration,
                preferredSize: record?.size
            )
        } else {
            outcome = engine.place(
                WindowPlacementEngine.Request(
                    target: target,
                    window: window,
                    processID: processID,
                    screen: screen,
                    preferredSize: record?.size
                )
            )
        }

        if let achieved = outcome.achievedFrame, let key = windowKey(for: window), achieved != .zero {
            stateLock.lock()
            history.recordPlacement(key: key, frame: achieved)
            stateLock.unlock()
        }

        recordResult(target, success: outcome.succeeded, reason: outcome.label, window: window)
        if outcome.succeeded {
            performHapticFeedback()
        }
    }

    /// The system's own tiling item, when the user asked for it and the target has one.
    private func nativeCommand(for target: SnapTarget, configuration: SnapConfiguration) -> NativeTilingCommand? {
        guard configuration.prefersNativeTiling, let action = target.action else { return nil }
        return NativeTilingCommand.matching(action)
    }

    private func placeNatively(
        _ command: NativeTilingCommand,
        target: SnapTarget,
        on window: AXUIElement,
        processID: pid_t,
        configuration: SnapConfiguration,
        preferredSize: CGSize?
    ) -> WindowPlacementEngine.Outcome {
        guard nativeTiling.supports(command, processID: processID),
              let before = WindowFrameResolver.frame(of: window)?.frame,
              nativeTiling.perform(command, processID: processID) else {
            return engine.place(
                WindowPlacementEngine.Request(
                    target: target,
                    window: window,
                    processID: processID,
                    preferredSize: preferredSize
                )
            )
        }
        confirmNativePlacement(
            target,
            window: window,
            before: before,
            processID: processID,
            configuration: configuration,
            preferredSize: preferredSize
        )
        return .placed(frame: before, path: "native")
    }

    /// A press is accepted even when the item is disabled, and the system then does nothing.
    /// macOS also animates by really moving the window, so the outcome cannot be read until the
    /// animation settles. Both facts are why this exists instead of trusting the press.
    private func confirmNativePlacement(
        _ target: SnapTarget,
        window: AXUIElement,
        before: CGRect,
        processID: pid_t,
        configuration: SnapConfiguration,
        preferredSize: CGSize?
    ) {
        stateLock.lock()
        let revision = placementRevision
        stateLock.unlock()
        Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            AXCommandQueue.shared.async { [weak self] in
                guard let self else { return }
                self.confirmNativeOnQueue(
                    target, window: window, before: before, processID: processID,
                    configuration: configuration, preferredSize: preferredSize, revision: revision
                )
            }
        }
    }

    private func confirmNativeOnQueue(
        _ target: SnapTarget, window: AXUIElement, before: CGRect, processID: pid_t,
        configuration: SnapConfiguration, preferredSize: CGSize?, revision: UInt64
    ) {
            stateLock.lock()
            let isCurrent = placementRevision == revision
            stateLock.unlock()
            guard isCurrent, let after = WindowFrameResolver.frame(of: window)?.frame else { return }

            if !WindowSnapGeometry.framesApproximatelyEqual(after, before, tolerance: 1) {
                // It moved. Record where it landed so `restore` compares against the right frame.
                if let key = self.windowKey(for: window) {
                    self.stateLock.lock()
                    self.history.recordPlacement(key: key, frame: after)
                    self.stateLock.unlock()
                }
                return
            }

            self.logger.debug("Native tiling left the window in place; placing it directly")
            let outcome = self.engine.place(
                WindowPlacementEngine.Request(
                    target: target,
                    window: window,
                    processID: processID,
                    preferredSize: preferredSize
                )
            )
            if let achieved = outcome.achievedFrame, let key = self.windowKey(for: window) {
                self.stateLock.lock()
                self.history.recordPlacement(key: key, frame: achieved)
                self.stateLock.unlock()
            }
            self.recordResult(target, success: outcome.succeeded, reason: "native-\(outcome.label)", window: window)
    }

    /// Whether the target can be performed on this window at all. Menu validation reads this, so it
    /// must stay cheap and must not move anything.
    private func canPlace(_ target: SnapTarget, on window: AXUIElement, processID: pid_t) -> Bool {
        guard isFullScreen(window) != true else { return false }

        switch target {
        case .action(.restore):
            guard let key = windowKey(for: window),
                  let current = WindowFrameResolver.frame(of: window)?.frame else { return false }
            stateLock.lock()
            defer { stateLock.unlock() }
            return history.canRestore(key: key, currentFrame: current)
        case .action(.minimize):
            return isMinimized(window) != true
        case .action(.nextDisplay), .action(.previousDisplay):
            return ScreenGeometryProvider.cachedScreens().count > 1
        case .visibility:
            return true
        case .region, .action:
            guard isMinimized(window) != true else { return false }
            if let command = nativeCommand(for: target, configuration: currentConfiguration()),
               nativeTiling.supports(command, processID: processID) {
                return true
            }
            return WindowFrameResolver.isSettable(window)
        }
    }

    private func restore(_ window: AXUIElement) -> WindowPlacementEngine.Outcome {
        guard let key = windowKey(for: window),
              let current = WindowFrameResolver.frame(of: window)?.frame else {
            return .refused(reason: "noSavedFrame")
        }

        stateLock.lock()
        let original = history.takeRestoreFrame(key: key, currentFrame: current)
        stateLock.unlock()

        guard let original else {
            return .refused(reason: "stale")
        }
        guard let achieved = engine.apply(original, to: window) else { return .refused(reason: "setFrame") }
        guard WindowSnapGeometry.framesApproximatelyEqual(achieved, original, tolerance: 3) else {
            return .refused(reason: "unmoved")
        }
        return .placed(frame: achieved, path: "restore")
    }

    // MARK: - Target resolution

    /// The window an action should act on for an application.
    ///
    /// Falls back through focused → main → first usable window, because the menu bar icon acts on an
    /// app that is not frontmost, where neither of the first two is guaranteed to resolve.
    func focusedWindow(forApplication processID: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processID)
        if let focused: AXUIElement = AXElementReader.attribute(kAXFocusedWindowAttribute, from: application),
           rejection(for: focused, processID: processID) == nil {
            return focused
        }
        if let main: AXUIElement = AXElementReader.attribute(kAXMainWindowAttribute, from: application),
           rejection(for: main, processID: processID) == nil {
            return main
        }
        let windows = AXElementReader.elements(kAXWindowsAttribute, from: application)
        return windows.first { rejection(for: $0, processID: processID) == nil }
    }

    /// Every window of an application that the engine is willing to touch, in AX order.
    func eligibleWindows(forApplication processID: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(processID)
        return AXElementReader
            .elements(kAXWindowsAttribute, from: application)
            .filter { rejection(for: $0, processID: processID) == nil }
    }

    // MARK: - Window attributes

    private func isFullScreen(_ window: AXUIElement) -> Bool? {
        AXElementReader.attribute(fullScreenAttribute, from: window)
    }

    private func isMinimized(_ window: AXUIElement) -> Bool? {
        AXElementReader.attribute(kAXMinimizedAttribute, from: window)
    }

    private func processIdentifier(of window: AXUIElement) -> pid_t? {
        AXElementReader.processIdentifier(of: window)
    }

    private func windowKey(for window: AXUIElement) -> WindowKey? {
        guard let processID = AXElementReader.processIdentifier(of: window) else { return nil }
        return WindowKey(processID: processID, element: window)
    }

    private var fullScreenAttribute: String { "AXFullScreen" }

    // MARK: - Diagnostics and feedback

    private func recordRequest(_ target: SnapTarget, zone: SnapGestureZone? = nil) {
        var fields = ["snapTarget": target.diagnosticName]
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
    private func recordResult(
        _ target: SnapTarget,
        success: Bool,
        reason: String = "",
        window: AXUIElement? = nil
    ) {
        var fields = ["snapTarget": target.diagnosticName, "reason": reason]
        if !success {
            fields["screens"] = String(ScreenGeometryProvider.cachedScreens().count)
            fields["primaryMaxY"] = String(format: "%.0f", ScreenGeometryProvider.flipReferenceMaxY())
            if let window, let frame = WindowFrameResolver.frame(of: window)?.frame {
                fields["windowFrame"] = describe(frame)
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
