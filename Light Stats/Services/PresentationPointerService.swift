//
//  PresentationPointerService.swift
//  Light Stats
//
//  Persistent presentation pointer: the asset pack's animated diamond cursor
//  follows the system pointer in a click-through overlay window, and the real
//  pointer is hidden while it runs. No event tap and no permission — the overlay
//  reads `NSEvent.mouseLocation`, and Core Animation plays the 48-frame atlas, so
//  the steady state runs no per-frame Swift drawing.
//

import AppKit
import QuartzCore

@MainActor
protocol PresentationPointerControlling: AnyObject {
    var isRunning: Bool { get }
    func start()
    func stop()
    func updateCursorStyle(_ style: PresentationCursorStyle)
}

/// Owns one small transparent window whose arrow tip sits on the pointer hotspot.
@MainActor
final class PresentationPointerService: PresentationPointerControlling {
    private static let frameAnimationKey = "presentationCursorFrames"
    private static let trackingIntervalNanoseconds: UInt64 = 16_666_667
    /// How often the hidden state is re-asserted while the pointer moves. Two window-server
    /// calls at this rate are nothing next to the 60 Hz tracking below.
    private static let cursorReassertInterval: TimeInterval = 0.5

    private let logger = AppLogger(category: "PresentationPointer")
    private var style: PresentationCursorStyle = .shippedDefault

    private(set) var isRunning = false
    private var overlayWindow: NSWindow?
    private var cursorLayer: CALayer?
    private var trackingTask: Task<Void, Never>?
    private var lastPointerLocation: CGPoint?
    private var isSystemCursorHidden = false
    private var nextCursorReassertAt: TimeInterval = 0
    private var sessionObservers: [NSObjectProtocol] = []
    private var cursorControl = BackgroundCursorControl()

    func start() {
        guard !isRunning else { return }
        guard let frames = PresentationCursorAtlas.loadFrames(for: style), !frames.isEmpty else {
            logger.error("Presentation cursor atlas unavailable; presentation pointer stays off")
            return
        }

        isRunning = true
        let window = makeOverlayWindow(frames: frames)
        overlayWindow = window
        updatePointerLocation()
        window.orderFrontRegardless()
        hideSystemCursor()
        observeSessionEnd()
        startTracking()
        logger.info("Presentation pointer started: \(style.rawValue)")
    }

    /// Swap the colourway live. The window stays where it is; only the layer's contents
    /// and the hotspot change, and a style whose art is missing leaves the current one
    /// on screen rather than blanking the pointer.
    func updateCursorStyle(_ style: PresentationCursorStyle) {
        guard style != self.style else { return }
        guard isRunning, let window = overlayWindow else {
            self.style = style
            return
        }
        guard let frames = PresentationCursorAtlas.loadFrames(for: style), !frames.isEmpty else {
            logger.error("Presentation cursor atlas missing for \(style.rawValue); keeping the current style")
            return
        }
        self.style = style
        lastPointerLocation = nil
        replaceCursorLayer(frames: frames, in: window)
    }

    func stop() {
        guard isRunning || overlayWindow != nil else { return }
        isRunning = false
        trackingTask?.cancel()
        trackingTask = nil
        lastPointerLocation = nil
        removeSessionObservers()
        showSystemCursor()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        cursorLayer = nil
        logger.info("Presentation pointer stopped")
    }

    // MARK: - Window

    private func makeOverlayWindow(frames: [CGImage]) -> NSWindow {
        let size = CGSize(
            width: PresentationCursorGeometry.renderSize,
            height: PresentationCursorGeometry.renderSize
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSView(frame: CGRect(origin: .zero, size: size))
        host.wantsLayer = true
        window.contentView = host
        let cursor = makeCursorLayer(frames: frames, size: size, contentsScale: window.backingScaleFactor)
        host.layer?.addSublayer(cursor)
        cursorLayer = cursor
        return window
    }

    private func makeCursorLayer(frames: [CGImage], size: CGSize, contentsScale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contentsScale = contentsScale
        layer.contentsGravity = .resizeAspect
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear
        layer.contents = frames.first
        layer.add(Self.frameAnimation(frames: frames), forKey: Self.frameAnimationKey)
        return layer
    }

    private func replaceCursorLayer(frames: [CGImage], in window: NSWindow) {
        guard let host = window.contentView, let hostLayer = host.layer else { return }
        let replacement = makeCursorLayer(
            frames: frames,
            size: host.bounds.size,
            contentsScale: window.screen?.backingScaleFactor ?? window.backingScaleFactor
        )
        hostLayer.addSublayer(replacement)
        cursorLayer?.removeFromSuperlayer()
        cursorLayer = replacement
    }

    /// One discrete keyframe sequence over `contents`: the render server plays all
    /// 48 frames on its own clock, so nothing here runs per frame.
    private static func frameAnimation(frames: [CGImage]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = PresentationCursorAtlas.keyTimes(frameCount: frames.count)
        animation.calculationMode = .discrete
        animation.duration = PresentationCursorAtlas.loopDuration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    // MARK: - Tracking

    private func startTracking() {
        trackingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updatePointerLocation()
                try? await Task.sleep(nanoseconds: Self.trackingIntervalNanoseconds)
            }
        }
    }

    private func updatePointerLocation() {
        guard isRunning, let window = overlayWindow else { return }
        let pointer = NSEvent.mouseLocation
        if let lastPointerLocation,
           abs(pointer.x - lastPointerLocation.x) < 0.25,
           abs(pointer.y - lastPointerLocation.y) < 0.25 {
            return
        }
        lastPointerLocation = pointer
        let hotspot = PresentationCursorGeometry.hotspot(cellHotspot: style.cellHotspot)
        window.setFrameOrigin(
            PresentationCursorGeometry.windowOrigin(pointer: pointer, hotspot: hotspot)
        )
        syncCursorLayerScale(for: window)
        reassertHiddenCursorIfNeeded(at: pointer)
    }

    /// Moving the window between displays with different backing scales re-renders the
    /// 128px art at the new scale instead of resampling blur.
    private func syncCursorLayerScale(for window: NSWindow) {
        guard let cursorLayer, let scale = window.screen?.backingScaleFactor,
              cursorLayer.contentsScale != scale else {
            return
        }
        cursorLayer.contentsScale = scale
    }

    // MARK: - System cursor

    /// No window can cover the system cursor — the window server draws it above every
    /// window level — so the diamond only replaces the cursor while the real one is
    /// hidden. That needs two things: the process-wide background grant (a never-active
    /// menu-bar app's `CGDisplayHideCursor` is otherwise a silent no-op), and a show for
    /// every hide on every stop path (toggle, switch off, license loss, tap death,
    /// session end, app exit).
    private func hideSystemCursor() {
        guard !isSystemCursorHidden else { return }
        let controlsCursor = cursorControl.enableOnce()
        let error = CGDisplayHideCursor(CGMainDisplayID())
        isSystemCursorHidden = error == .success
        if !isSystemCursorHidden {
            logger.error("CGDisplayHideCursor failed with error \(error.rawValue)")
        }
        if !controlsCursor {
            logger.error("Without the background grant the system arrow stays over the presentation pointer")
        }
    }

    private func showSystemCursor() {
        guard isSystemCursorHidden else { return }
        isSystemCursorHidden = false
        let error = CGDisplayShowCursor(CGMainDisplayID())
        if error != .success {
            logger.error("CGDisplayShowCursor failed with error \(error.rawValue)")
        }
    }

    /// The window server can hand cursor control to something else — the Dock, a window
    /// edge's resize cursor, another owner — and because our hide is a count the window
    /// server already consumed, the real arrow then comes back *and stays back* even once
    /// that owner lets go. Nothing reports that, so re-assert on movement: a show/hide
    /// pair leaves the count exactly where it was while forcing the window server to
    /// re-decide which cursor to draw.
    private func reassertHiddenCursorIfNeeded(at pointer: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        guard isSystemCursorHidden, now >= nextCursorReassertAt else { return }
        nextCursorReassertAt = now + Self.cursorReassertInterval

        let wasVisible = BackgroundCursorControl.isSystemCursorVisible() == true
        let showError = CGDisplayShowCursor(CGMainDisplayID())
        let hideError = CGDisplayHideCursor(CGMainDisplayID())
        guard showError == .success, hideError == .success else {
            logger.error(
                "Re-asserting the hidden cursor failed (show \(showError.rawValue), hide \(hideError.rawValue))"
            )
            return
        }
        if wasVisible {
            logger.info(
                "Cursor had come back at \(Int(pointer.x)),\(Int(pointer.y)); re-asserted the hidden state"
            )
        }
    }

    /// A hidden system cursor must not outlive the session that drew its replacement:
    /// the lock screen, a fast-user switch, and display sleep all end the pointer.
    private func observeSessionEnd() {
        guard sessionObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            sessionObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stop() }
                }
            )
        }
    }

    private func removeSessionObservers() {
        guard !sessionObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionObservers.forEach(center.removeObserver)
        sessionObservers.removeAll()
    }
}
