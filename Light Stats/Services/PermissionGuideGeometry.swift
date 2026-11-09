//
//  PermissionGuideGeometry.swift
//  Light Stats
//

import CoreGraphics

/// The two shapes the guide card has: the frames it draws on the way out, and the slot it rests in.
///
/// Both are pure functions of values, so the whole feel of the movement and the whole placement rule
/// are verifiable without a display — the panel that plays them is AppKit and untested. This is the
/// same split the window-snap group uses (`SnapAnimationCurve`, `SnapGridGeometry`): the model holds
/// the endpoints, Services owns the arithmetic.
///
/// Every rectangle here is in **Cocoa screen points** (origin bottom-left, `y` up).
nonisolated enum PermissionGuideGeometry {

    // MARK: - Sampling

    /// One frame of the flight.
    ///
    /// No `scale`: the arrival overshoot is folded into the *size*, so the card can grow past its
    /// target and settle back without ever drawing outside the panel that carries it.
    struct Sample: Equatable, Sendable {
        var frame: CGRect
        var cornerRadius: CGFloat
        /// `0` at both ends, peak in the middle — the card floats while it travels and rests flat.
        var shadowOpacity: Double
    }

    static func sample(_ flight: PermissionGuideFlight, atProgress progress: Double) -> Sample {
        let t = min(max(progress, 0), 1)
        let eased = easeInOut(t)
        let envelope = springEnvelope(t)
        let width = flight.startFrame.width + (flight.endFrame.width - flight.startFrame.width) * envelope
        let height = flight.startFrame.height + (flight.endFrame.height - flight.startFrame.height) * envelope
        let centre = point(
            from: flight.startFrame,
            to: flight.endFrame,
            control: controlPoint(for: flight),
            at: eased
        )
        let radius = PermissionGuideFlight.startCornerRadius
            + (PermissionGuideFlight.endCornerRadius - PermissionGuideFlight.startCornerRadius) * eased

        return Sample(
            frame: CGRect(
                x: centre.x - width / 2,
                y: centre.y - height / 2,
                width: width,
                height: height
            ),
            cornerRadius: radius,
            shadowOpacity: 4 * t * (1 - t)
        )
    }

    /// The Bézier control point: above the higher of the two endpoints, so the arc clears both.
    static func controlPoint(for flight: PermissionGuideFlight) -> CGPoint {
        CGPoint(
            x: (flight.startFrame.midX + flight.endFrame.midX) / 2,
            y: max(flight.startFrame.maxY, flight.endFrame.maxY) + flight.apexHeight
        )
    }

    /// Position at `t` on the quadratic Bézier through `control`.
    static func point(from start: CGRect, to end: CGRect, control: CGPoint, at t: Double) -> CGPoint {
        let origin = CGPoint(x: start.midX, y: start.midY)
        let target = CGPoint(x: end.midX, y: end.midY)
        let inverse = 1 - t
        let startWeight = inverse * inverse
        let controlWeight = 2 * inverse * t
        let endWeight = t * t
        return CGPoint(
            x: startWeight * origin.x + controlWeight * control.x + endWeight * target.x,
            y: startWeight * origin.y + controlWeight * control.y + endWeight * target.y
        )
    }

    /// The classic ease-in-out cubic: position and corner radius both feed on it, so the card
    /// accelerates away from the click and decelerates into the slot.
    static func easeInOut(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        if clamped < 0.5 { return 4 * clamped * clamped * clamped }
        let inverse = -2 * clamped + 2
        return 1 - inverse * inverse * inverse / 2
    }

    /// Underdamped step response of a spring, normalised so it starts at exactly `0` and lands on
    /// exactly `1`.
    ///
    /// Critical damping would stop the card dead on the pixel. ζ = 0.7 gives one small overshoot
    /// (about 2% of the travelled size, peaking at three quarters of the flight), which is what an
    /// object arriving under its own momentum does. The normalisation is load-bearing twice over:
    /// the closed form only converges on 1 asymptotically, and the last frame must *be* the target.
    static func springEnvelope(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return rawSpring(clamped) / rawSpring(1)
    }

    private static func rawSpring(_ t: Double) -> Double {
        let damping = 0.7
        let omega = 5.9
        let damped = omega * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * omega * t)
        return 1 - decay * (cos(damped * t) + damping * omega / damped * sin(damped * t))
    }

    // MARK: - Docking

    /// The slot the card rests in, and which way the list lies from it.
    struct Dock: Equatable, Sendable {
        var frame: CGRect
        var side: PermissionGuideDockSide
    }

    /// The gap between the card and the window it points at, and the smallest distance the card is
    /// allowed to sit from the screen edge.
    static let dockInset: CGFloat = 16
    static let screenEdge: CGFloat = 8

    /// The first free side of the window, in the order the card prefers them.
    ///
    /// Below first, right-aligned with the window — the card then points up at the list it is asking
    /// the user to drag into. The rest of the order exists for one reason: **the card may never
    /// cover the window.** It is a mouse-opaque panel above the Settings window, so a card drawn
    /// over the window would swallow the drop target and the TCC sheet's buttons — which is exactly
    /// what the old clamp-only fallback did whenever the window sat towards the left of the screen.
    ///
    /// A candidate is only accepted if it is fully on screen and does not intersect the window at
    /// all. When no side satisfies both (a window filling the screen), the below slot is clamped into
    /// the visible frame: a card half off the screen is worse than one overlapping its target.
    static func dock(cardSize: CGSize, beside settingsFrame: CGRect, visibleFrame: CGRect) -> Dock {
        let bounds = visibleFrame.insetBy(dx: screenEdge, dy: screenEdge)

        for side in PermissionGuideDockSide.allCases {
            let frame = unclampedFrame(side: side, cardSize: cardSize, beside: settingsFrame)
            guard bounds.contains(frame), !frame.intersects(settingsFrame) else { continue }
            return Dock(frame: frame, side: side)
        }

        let below = PermissionGuideDockSide.below
        return Dock(
            frame: clampedFrame(unclampedFrame(side: below, cardSize: cardSize, beside: settingsFrame),
                                into: visibleFrame),
            side: below
        )
    }

    /// The slot for one side, before anything has been moved to keep it on screen.
    private static func unclampedFrame(side: PermissionGuideDockSide,
                                       cardSize: CGSize,
                                       beside settingsFrame: CGRect) -> CGRect {
        switch side {
        case .below:
            return CGRect(
                x: settingsFrame.maxX - cardSize.width - dockInset,
                y: settingsFrame.minY - cardSize.height - dockInset,
                width: cardSize.width,
                height: cardSize.height
            )
        case .above:
            return CGRect(
                x: settingsFrame.maxX - cardSize.width - dockInset,
                y: settingsFrame.maxY + dockInset,
                width: cardSize.width,
                height: cardSize.height
            )
        case .left:
            return CGRect(
                x: settingsFrame.minX - cardSize.width - dockInset,
                y: settingsFrame.maxY - cardSize.height - dockInset,
                width: cardSize.width,
                height: cardSize.height
            )
        case .right:
            return CGRect(
                x: settingsFrame.maxX + dockInset,
                y: settingsFrame.maxY - cardSize.height - dockInset,
                width: cardSize.width,
                height: cardSize.height
            )
        }
    }

    private static func clampedFrame(_ frame: CGRect, into visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: clamp(frame.origin.x, visibleFrame.minX + screenEdge,
                     visibleFrame.maxX - frame.width - screenEdge),
            y: clamp(frame.origin.y, visibleFrame.minY + screenEdge,
                     visibleFrame.maxY - frame.height - screenEdge),
            width: frame.width,
            height: frame.height
        )
    }

    private static func clamp(_ value: CGFloat, _ lowest: CGFloat, _ highest: CGFloat) -> CGFloat {
        guard highest > lowest else { return lowest }
        return min(max(value, lowest), highest)
    }
}
