//
//  WindowPlacementEngine.swift
//  Light Stats
//

import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

/// Writes window frames.
///
/// This is the only place in the app that moves another app's window, and it moves it **itself**
/// rather than pressing the system's tiling menu item. That inversion is deliberate:
///
/// - the system's menu item reports success for a window it then does not move, because the target
///   app was not frontmost, and the failure only shows up about 600 ms later;
/// - the system has no command at all for thirds, custom layouts, gaps, or display moves;
/// - the system's own animation makes the resulting frame unreadable until it settles.
///
/// `NativeWindowTilingService` is kept as an opt-in accelerator for users who want the system's
/// animation, not as the default path.
nonisolated final class WindowPlacementEngine: @unchecked Sendable {

    /// What became of one placement attempt. Internal so tests can assert on the path taken.
    enum Outcome {
        /// The window moved. The label names the path that produced it.
        case placed(frame: CGRect, path: String)
        /// Nothing moved. The label is a stable reason code.
        case refused(reason: String)

        var succeeded: Bool {
            switch self {
            case .placed: return true
            case .refused: return false
            }
        }

        var label: String {
            switch self {
            case .placed(_, let path): return path
            case .refused(let reason): return reason
            }
        }

        var achievedFrame: CGRect? {
            switch self {
            case .placed(let frame, _): return frame
            case .refused: return nil
            }
        }
    }

    struct Request {
        var target: SnapTarget
        var window: AXUIElement
        var processID: pid_t
        /// Explicit target display — the drag pipeline knows which display the pointer is on.
        /// `nil` means "the display the window is already on".
        var screen: SnapScreenGeometry?
        var margins: SnapMargins
        /// Size to use for `.center`, so centring a window that was just maximized returns it to
        /// its pre-snap size instead of leaving it full-width.
        var preferredSize: CGSize?
        /// Where the window stood when the drag that asked for this placement began.
        ///
        /// The drop path cannot wait for a frame sample to prove the gesture moved a window: a flick
        /// to the edge can end inside one sample interval. So the proof is made here instead, at the
        /// frame read this path already performs — a window still sitting where the drag started is
        /// text selection or a click, not a move, and is refused.
        var originFrame: CGRect?

        init(
            target: SnapTarget,
            window: AXUIElement,
            processID: pid_t,
            screen: SnapScreenGeometry? = nil,
            margins: SnapMargins = .zero,
            preferredSize: CGSize? = nil,
            originFrame: CGRect? = nil
        ) {
            self.target = target
            self.window = window
            self.processID = processID
            self.screen = screen
            self.margins = margins
            self.preferredSize = preferredSize
            self.originFrame = originFrame
        }
    }

    private let logger = AppLogger(category: "WindowPlacement")

    /// Runs the whole placement on the shared AX queue.
    ///
    /// Reading the window, deciding the frame, and writing it have to happen without a drag sample
    /// cutting in between — otherwise the frame read that decides a snap can be the frame from
    /// halfway through a previous write. `AXCommandQueue` is the same queue the drag pipeline reads
    /// on, so one lock orders both.
    func place(_ request: Request) -> Outcome {
        AXCommandQueue.shared.sync { placeOnQueue(request) }
    }

    private func placeOnQueue(_ request: Request) -> Outcome {
        switch request.target {
        case .action(.restore):
            // Restore needs the window's history, which the orchestrator owns.
            return .refused(reason: "restore-handled-elsewhere")
        case .action(.minimize):
            return minimize(request.window)
        case .action(.nextDisplay):
            return moveToAdjacentDisplay(request, direction: 1)
        case .action(.previousDisplay):
            return moveToAdjacentDisplay(request, direction: -1)
        case .action, .region:
            return placeInRegion(request)
        case .visibility:
            // Handled by the orchestrator: hiding applications is not a placement.
            return .refused(reason: "visibility-handled-elsewhere")
        }
    }

    /// Frame a target resolves to, or `nil` when the target is not a region at all.
    ///
    /// Public so the preview overlay and the island can draw the exact rectangle the engine will
    /// write, so the footprint the user aims at is always the rectangle the window becomes.
    ///
    /// `margins` defaults to the product's only value: the gap is not a preference, and the system's
    /// own placement path has no gap setting to mirror.
    static func resolvedFrame(
        for target: SnapTarget,
        screen: SnapScreenGeometry,
        margins: SnapMargins = .zero,
        currentSize: CGSize,
        preferredSize: CGSize? = nil
    ) -> CGRect? {
        let bounds = screen.visibleFrame
        switch target {
        case .region(let rect):
            return SnapGridGeometry.frame(for: rect, in: bounds, margins: margins)
        case .action(let action):
            if action == .center {
                let size = preferredSize ?? currentSize
                return WindowSnapGeometry.centeredFrame(
                    size: size,
                    in: SnapGridGeometry.insetBounds(bounds, margins: margins)
                )
            }
            if action == .restore || action == .minimize {
                return bounds
            }
            return WindowSnapGeometry.regionFrame(for: action, bounds: bounds, margins: margins)
        case .visibility:
            return nil
        }
    }

    // MARK: - Region placement

    private func placeInRegion(_ request: Request) -> Outcome {
        var current = WindowFrameResolver.frame(of: request.window)?.frame
        if current == nil {
            // Electron and Java apps expose almost nothing until this flag is set, and it is a
            // property of the target application — so it is applied lazily, on the first window
            // that would otherwise be unreadable, and then retried once.
            WindowFrameResolver.enableEnhancedUserInterface(for: request.processID)
            current = WindowFrameResolver.frame(of: request.window)?.frame
        }
        guard let current else {
            return .refused(reason: "noFrame")
        }
        if let originFrame = request.originFrame,
           WindowSnapGeometry.framesApproximatelyEqual(current, originFrame, tolerance: 2) {
            return .refused(reason: "unmoved")
        }
        guard let screen = request.screen ?? ScreenGeometryProvider.screen(containing: current) else {
            return .refused(reason: "noScreen")
        }
        guard let targetFrame = Self.resolvedFrame(
            for: request.target,
            screen: screen,
            margins: request.margins,
            currentSize: current.size,
            preferredSize: request.preferredSize
        ) else {
            return .refused(reason: "noTargetFrame")
        }

        guard var achieved = apply(targetFrame, to: request.window) else {
            return .refused(reason: "setFrame")
        }
        if !WindowSnapGeometry.framesApproximatelyEqual(achieved, targetFrame) {
            let adjusted = WindowPlacementAdjustment.frame(
                target: targetFrame, acceptedSize: achieved.size, screen: screen.visibleFrame,
                isResizable: AXElementReader.isSettable(kAXSizeAttribute, of: request.window)
            )
            if setPosition(adjusted.origin, for: request.window),
               let confirmed = WindowFrameResolver.frameFromAttributes(of: request.window) {
                achieved = confirmed
            }
        }
        if WindowSnapGeometry.framesApproximatelyEqual(achieved, targetFrame) {
            return .placed(frame: achieved, path: "local")
        }
        if WindowSnapGeometry.framesApproximatelyEqual(achieved, current, tolerance: 1) {
            return .refused(reason: "unmoved")
        }
        logger.debug("Window accepted a clamped frame \(achieved) for target \(targetFrame)")
        return .placed(frame: achieved, path: "localClamped")
    }

    // MARK: - Minimize

    private func minimize(_ window: AXUIElement) -> Outcome {
        let minimized = kCFBooleanTrue as CFTypeRef
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized)
        return result == .success ? .placed(frame: .zero, path: "minimize") : .refused(reason: "minimize")
    }

    // MARK: - Display moves

    private func moveToAdjacentDisplay(_ request: Request, direction: Int) -> Outcome {
        guard let current = WindowFrameResolver.frame(of: request.window)?.frame else {
            return .refused(reason: "noFrame")
        }
        let screens = ScreenGeometryProvider.cachedScreens()
        guard screens.count > 1,
              let currentScreen = ScreenGeometryProvider.screen(containing: current),
              let currentIndex = screens.firstIndex(of: currentScreen) else {
            return .refused(reason: "display")
        }

        let targetIndex = (currentIndex + direction + screens.count) % screens.count
        let targetScreen = screens[targetIndex]

        // A display move is a *transfer*, not a tile: the window keeps its relative position and
        // size. The margins are therefore applied by shrinking both usable areas, so a half-tile on
        // one display arrives as a half-tile on the next, inside the same gaps.
        let sourceArea = SnapGridGeometry.insetBounds(currentScreen.visibleFrame, margins: request.margins)
        let targetArea = SnapGridGeometry.insetBounds(targetScreen.visibleFrame, margins: request.margins)
        let targetFrame = WindowSnapGeometry.transferredFrame(current, from: sourceArea, to: targetArea)

        guard let achieved = apply(targetFrame, to: request.window) else {
            return .refused(reason: "setFrame")
        }
        guard !WindowSnapGeometry.framesApproximatelyEqual(achieved, current, tolerance: 1) else {
            return .refused(reason: "unmoved")
        }
        return .placed(frame: achieved, path: "display")
    }

    // MARK: - Frame writes

    /// How many times a frame is re-asserted before whatever the window will take is accepted.
    private static let writeAttempts = 6
    /// Pause before reading the frame back, and between attempts.
    ///
    /// Apps animate their own resize, so a reading taken immediately after the write can still be a
    /// frame in flight. Measured on Grok Bot with the enhanced-UI flag already suspended, the window
    /// still converged over a few attempts (1345 → 1618 → 1656 → 1662 points of height), so the loop
    /// needs room; a window that takes the write straight away pays one pause and stops.
    private static let settleMicros: useconds_t = 90_000

    /// Writes a frame and reports what the window actually ended up with.
    ///
    /// Size first, then position, then size again — macOS enforces sizes that fit on the current
    /// display, so a window moving between displays needs the size re-asserted after it has moved —
    /// and the frame is read back and re-asserted until the window agrees.
    ///
    /// **`AXEnhancedUserInterface` is turned off for the duration of the write.** While that flag is
    /// on, an app accepts `AXSize` and silently keeps its old size: the position lands, the size does
    /// not, so the window ends up in a different shape in a different place — or does not move at
    /// all. Measured on this machine with everything else identical: Finder and Grok Bot both refuse
    /// the write with the flag on (0,230 787x704 and 0,552 1201x950) and both land exactly on target
    /// with it off. `WindowFrameResolver.enableEnhancedUserInterface` switches that flag on in order
    /// to read Electron window trees, which is why real applications were the ones that broke while a
    /// plain editor never did. Rectangle, which is open source, disables the same flag around every
    /// adjustment for the same reason and restores it afterwards.
    @discardableResult
    func apply(_ frame: CGRect, to window: AXUIElement) -> CGRect? {
        AXCommandQueue.shared.sync { applyOnQueue(frame, to: window) }
    }

    private func applyOnQueue(_ frame: CGRect, to window: AXUIElement) -> CGRect? {
        let resizable = AXElementReader.isSettable(kAXSizeAttribute, of: window)
        let movable = AXElementReader.isSettable(kAXPositionAttribute, of: window)
        guard resizable || movable else { return nil }

        let enhancedUI = suspendEnhancedUserInterface(for: window)
        defer { restoreEnhancedUserInterface(enhancedUI, for: window) }

        var achieved: CGRect?
        for _ in 0..<Self.writeAttempts {
            if resizable { _ = setSize(frame.size, for: window) }
            if movable { _ = setPosition(frame.origin, for: window) }
            if resizable { _ = setSize(frame.size, for: window) }

            // Some apps animate their own resize, so a reading taken right after the write can still
            // be a frame in flight. The pause only costs anything when the first attempt did not
            // land; a window that takes the write straight away is done here.
            usleep(Self.settleMicros)
            let previous = achieved
            achieved = WindowFrameResolver.frameFromAttributes(of: window)
            guard let achieved else { continue }
            if WindowSnapGeometry.framesApproximatelyEqual(achieved, frame) { return achieved }
            // Two readings in a row that agree with each other but not with the target mean the
            // window has settled somewhere else — it clamps its own size — and re-asserting the same
            // frame cannot move it.
            if let previous, WindowSnapGeometry.framesApproximatelyEqual(previous, achieved, tolerance: 1) {
                return achieved
            }
        }
        return achieved
    }

    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

    /// Turns the app's `AXEnhancedUserInterface` off and reports what it was, so the caller can put
    /// it back. `nil` means the app does not answer for the attribute.
    private func suspendEnhancedUserInterface(for window: AXUIElement) -> Bool? {
        guard let processID = AXElementReader.processIdentifier(of: window) else { return nil }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.2)
        let enabled: Bool? = AXElementReader.attribute(Self.enhancedUserInterfaceAttribute, from: application)
        guard enabled == true else { return enabled }
        _ = AXUIElementSetAttributeValue(
            application,
            Self.enhancedUserInterfaceAttribute as CFString,
            kCFBooleanFalse
        )
        return true
    }

    /// Puts the flag back the way it was found. It stays on for apps whose Accessibility tree only
    /// becomes usable with it, because the frame reads this placement path depends on would otherwise
    /// stop resolving; every write suspends it again for the duration of the write itself.
    private func restoreEnhancedUserInterface(_ enabled: Bool?, for window: AXUIElement) {
        guard enabled == true, let processID = AXElementReader.processIdentifier(of: window) else { return }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.2)
        _ = AXUIElementSetAttributeValue(
            application,
            Self.enhancedUserInterfaceAttribute as CFString,
            kCFBooleanTrue
        )
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
}
