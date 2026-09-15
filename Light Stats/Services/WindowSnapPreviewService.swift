//
//  WindowSnapPreviewService.swift
//  Light Stats
//

import AppKit

/// The translucent footprint that shows where a dragged or swiped window will land.
///
/// Rewritten around `SnapAnimationPlan` + `SnapAnimationDriver`. The previous version set the frame
/// with `setFrame(_:display:)` and only animated alpha, so changing target mid-drag snapped the
/// rectangle to the new place. Now the rectangle travels, and a target change mid-flight continues
/// from wherever it got to instead of restarting.
///
/// Frames are in **Cocoa** screen space, because that is what `NSWindow.setFrame` takes; callers
/// coming from Accessibility geometry convert with `ScreenGeometryProvider.toCocoa`.
@MainActor
final class WindowSnapPreviewService {

    private var overlayWindow: NSWindow?
    private var driver = SnapAnimationDriver()
    private var displayedFrame: CGRect = .zero
    /// Where the running animation is heading. A drag publishes an update every few points of
    /// pointer travel, and restarting the plan each time would reset its progress to zero — the
    /// footprint would crawl toward the target instead of travelling to it.
    private var targetFrame: CGRect?
    private var isShown = false

    var isVisible: Bool { isShown }

    /// Shows the footprint at `frame`, optionally growing out of `cameFrom` — normally the frame of
    /// the window being dragged, so the preview reads as the window stretching into place.
    func show(frame: CGRect, cameFrom: CGRect? = nil) {
        // Already heading exactly here — let the animation finish rather than restarting it.
        if isShown, targetFrame == frame { return }

        let window = overlayWindow ?? makeOverlayWindow()
        overlayWindow = window
        targetFrame = frame

        let start: CGRect
        let motion: SnapMotion
        let startAlpha: Double

        if isShown {
            // Continue from wherever the rectangle currently is, so a target change travels.
            start = displayedFrame
            motion = .resize
            startAlpha = Double(window.alphaValue)
        } else {
            start = cameFrom ?? frame
            motion = .show
            startAlpha = 0
            window.setFrame(start, display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
            window.invalidateShadow()
        }

        isShown = true
        displayedFrame = start

        let plan = SnapAnimationPlan(
            startFrame: start,
            targetFrame: frame,
            startAlpha: startAlpha,
            targetAlpha: 1,
            motion: motion,
            timing: .preview
        )

        driver.run(plan: plan) { [weak self, weak window] sample in
            guard let window else { return }
            self?.displayedFrame = sample.frame
            window.alphaValue = CGFloat(sample.alpha)
            window.setFrame(sample.frame, display: true)
        }
    }

    func hide() {
        guard isShown, let window = overlayWindow else { return }
        isShown = false
        targetFrame = nil

        let plan = SnapAnimationPlan(
            startFrame: displayedFrame,
            targetFrame: displayedFrame,
            startAlpha: Double(window.alphaValue),
            targetAlpha: 0,
            motion: .hide,
            timing: .preview,
            animatesGeometry: false
        )

        driver.run(plan: plan) { [weak window] sample in
            window?.alphaValue = CGFloat(sample.alpha)
        } onFinish: { [weak self, weak window] in
            window?.orderOut(nil)
            self?.displayedFrame = .zero
        }
    }

    /// Drops the overlay without animating — used when the whole feature is switched off.
    func dismissImmediately() {
        driver.cancel()
        overlayWindow?.orderOut(nil)
        overlayWindow?.alphaValue = 0
        overlayWindow = nil
        displayedFrame = .zero
        targetFrame = nil
        isShown = false
    }

    private func makeOverlayWindow() -> NSWindow {
        let view = SnapPreviewView(frame: .zero)
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = view
        return window
    }
}

/// A compositor-backed frosted footprint. Its frame is the exact placement rectangle.
private final class SnapPreviewView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 0.75
    }
}
