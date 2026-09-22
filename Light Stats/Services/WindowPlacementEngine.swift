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

        init(
            target: SnapTarget,
            window: AXUIElement,
            processID: pid_t,
            screen: SnapScreenGeometry? = nil,
            margins: SnapMargins = .zero,
            preferredSize: CGSize? = nil
        ) {
            self.target = target
            self.window = window
            self.processID = processID
            self.screen = screen
            self.margins = margins
            self.preferredSize = preferredSize
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

    /// Writes a frame and reports what the window actually ended up with.
    ///
    /// Size is written first and the pair twice: an app that re-clamps its origin after a resize —
    /// which is most of them — otherwise leaves the window at the right size in the wrong place.
    /// A window that cannot be resized still gets its position moved.
    @discardableResult
    func apply(_ frame: CGRect, to window: AXUIElement) -> CGRect? {
        AXCommandQueue.shared.sync { applyOnQueue(frame, to: window) }
    }

    private func applyOnQueue(_ frame: CGRect, to window: AXUIElement) -> CGRect? {
        let resizable = AXElementReader.isSettable(kAXSizeAttribute, of: window)
        let movable = AXElementReader.isSettable(kAXPositionAttribute, of: window)
        guard resizable || movable else { return nil }

        if resizable { _ = setSize(frame.size, for: window) }
        if movable { _ = setPosition(frame.origin, for: window) }
        if resizable { _ = setSize(frame.size, for: window) }
        if movable { _ = setPosition(frame.origin, for: window) }

        return WindowFrameResolver.frameFromAttributes(of: window)
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
