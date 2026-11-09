//
//  PermissionGuideWindow.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// The panel the guide card lives in.
///
/// A borderless `.nonactivatingPanel` for the reason every other overlay in this app is one: the
/// card is shown while System Settings is the active application, and a window that stole
/// activation would end the drag the card is asking the user to perform. `.floating` rather than the
/// `.statusBar` level the other panels use — the TCC privacy sheet is a system modal and must be
/// able to draw *over* the card.
///
/// `.transient` is deliberately absent from the collection behaviour: Stage Manager treats a
/// transient panel as belonging to our Stage, and the card would be pulled off to the side strip the
/// moment System Settings takes the foreground.
@MainActor
final class PermissionGuideWindow: NSPanel {

    /// 60 Hz, every frame computed from an absolute start time so a late tick lands on the right
    /// frame instead of leaving the animation behind. The panel resizes itself and re-renders a
    /// material card on each tick, so a faster clock buys nothing a 0.78 s flight can show and
    /// costs a second full layout pass per frame.
    private static let tickInterval: TimeInterval = 1.0 / 60.0
    private static let fadeDuration: TimeInterval = 0.18

    let cardState: PermissionGuideCardState
    private var hostingView: NSHostingView<PermissionGuideCardView>?

    private var ticker: Timer?
    private var watchdog: Task<Void, Never>?
    private var flight: PermissionGuideFlight?
    private var startedAt: TimeInterval = 0
    private var onFlightEnd: (() -> Void)?

    /// The drawn card's rectangle (Cocoa screen points), without the shadow margin.
    private(set) var cardFrame: CGRect = .zero

    var isFlying: Bool { flight != nil }

    init(cardState: PermissionGuideCardState) {
        self.cardState = cardState
        super.init(
            contentRect: CGRect(origin: .zero, size: PermissionGuideCardView.cardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        // The shadow is drawn in SwiftUI so it can follow the flight's bell curve; a window-level
        // shadow would sit at full strength while the card is still a dot.
        hasShadow = false
        // Nothing may interrupt the drag the card is asking for, and during the flight there is
        // nothing in it to click.
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        installContent()
    }

    /// A repeating `Timer` retains itself on the run loop, so a panel released with a live clock
    /// would keep waking the main thread at 60 Hz forever with nothing to draw.
    deinit {
        ticker?.invalidate()
        watchdog?.cancel()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The dock geometry is already clamped into the visible frame, with the shadow margin included.
    /// AppKit's own clamp to the visible area would move the card off the window it points at.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // MARK: - Placement

    /// The panel's frame is the card's frame plus the margin the shadow is drawn in.
    static func panelFrame(forCardFrame card: CGRect) -> CGRect {
        card.insetBy(dx: -PermissionGuideCardView.chromeInset, dy: -PermissionGuideCardView.chromeInset)
    }

    /// Snaps the card somewhere without animating — used while following the Settings window.
    func move(to card: CGRect) {
        guard !isFlying else { return }
        applyCardFrame(card)
    }

    // MARK: - Appearance

    /// Plays the flight, then hands control back.
    ///
    /// The panel is ordered front before the first frame: a `Timer` or display link that ticks
    /// against an off-screen panel advances the clock while nothing is visible.
    func fly(_ flight: PermissionGuideFlight, completion: (() -> Void)? = nil) {
        self.flight = flight
        onFlightEnd = completion
        ignoresMouseEvents = true
        alphaValue = 1
        apply(flight, at: 0)
        orderFrontRegardless()
        startedAt = ProcessInfo.processInfo.systemUptime
        startTicker()
        armWatchdog(duration: flight.duration)
    }

    /// No anchor to fly from: the card simply fades in where it docks.
    func fadeIn(at card: CGRect, completion: (() -> Void)? = nil) {
        onFlightEnd = completion
        applyCardFrame(card)
        cardState.cornerRadius = PermissionGuideFlight.endCornerRadius
        cardState.shadowOpacity = 0
        ignoresMouseEvents = true
        alphaValue = 0
        orderFrontRegardless()

        animateAlpha(to: 1)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeDuration))
            guard let self else { return }
            self.completeMotion()
        }
    }

    /// Reverses the flight back to wherever the card came from, then reports.
    func flyBack(to frame: CGRect, duration: TimeInterval? = nil, completion: (() -> Void)? = nil) {
        let flight = PermissionGuideFlight(
            startFrame: cardFrame,
            endFrame: frame,
            duration: duration ?? PermissionGuideFlight.reverseDuration
        )
        fly(flight, completion: completion)
    }

    func fadeOut(completion: (() -> Void)? = nil) {
        stopMotion()
        onFlightEnd = completion
        animateAlpha(to: 0)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeDuration))
            guard let self else { return }
            self.orderOut(nil)
            self.completeMotion()
        }
    }

    /// Stops the clock without finishing the motion.
    ///
    /// `teardown` calls this: dropping the last reference to a panel mid-flight would otherwise
    /// leave the ticker running and the flight's completion callback unreported.
    func stopMotion() {
        flight = nil
        onFlightEnd = nil
        stopTicker()
        watchdog?.cancel()
        watchdog = nil
    }

    /// The alpha ramp is AppKit's; everything it changes on the way is not.
    private func animateAlpha(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = alpha
        }
    }

    // MARK: - The frame clock

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        // Common modes so the flight keeps running while a menu is tracking or a drag is starting.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let flight else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        guard elapsed < flight.duration, flight.duration > 0 else {
            completeMotion()
            return
        }
        apply(flight, at: elapsed / flight.duration)
    }

    /// The clock is the authority on when the motion is over, exactly as it is for the island's
    /// spring: a flight whose progress crossed `1` would otherwise stop at the overshoot peak.
    private func completeMotion() {
        if let flight { apply(flight, at: 1) }
        flight = nil
        stopTicker()
        watchdog?.cancel()
        watchdog = nil
        ignoresMouseEvents = false
        let callback = onFlightEnd
        onFlightEnd = nil
        callback?()
    }

    /// A ticker that never fired must not leave the card hanging in mid-air.
    private func armWatchdog(duration: TimeInterval) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.3))
            guard !Task.isCancelled else { return }
            self?.completeMotion()
        }
    }

    // MARK: - Content

    private func installContent() {
        let hosting = NSHostingView(rootView: PermissionGuideCardView(state: cardState))
        // The flight decides the panel's size. Without this the hosting view resizes the window to
        // its content and every `setFrame` is undone on the next layout pass.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hosting
        hosting.frame = contentLayoutRect
        hostingView = hosting
    }

    private func apply(_ flight: PermissionGuideFlight, at progress: Double) {
        let sample = PermissionGuideGeometry.sample(flight, atProgress: progress)
        applyCardFrame(sample.frame)
        cardState.cornerRadius = sample.cornerRadius
        cardState.shadowOpacity = sample.shadowOpacity
    }

    private func applyCardFrame(_ card: CGRect) {
        cardFrame = card
        setFrame(Self.panelFrame(forCardFrame: card), display: true)
    }
}
