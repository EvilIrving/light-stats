//
//  SnapAnimationPlan.swift
//  Light Stats
//

import CoreGraphics

/// A fully described transition: where a window or panel starts, where it ends, and how it gets
/// there.
///
/// The plan is a value, which is the point. A `Timer` plus closures would drive the island and
/// leave none of it testable; here the frames, the alpha, and the interrupt behaviour are all readable
/// from a value that a test can construct and sample.
nonisolated struct SnapAnimationPlan: Hashable, Sendable {

    var startFrame: CGRect
    var targetFrame: CGRect
    var startAlpha: Double
    var targetAlpha: Double
    var motion: SnapMotion
    var timing: SnapTiming
    /// A hide-only transition keeps the frame and moves the alpha; animating geometry there looks
    /// like the panel is being sucked off screen.
    var animatesGeometry: Bool

    init(
        startFrame: CGRect,
        targetFrame: CGRect,
        startAlpha: Double = 1,
        targetAlpha: Double = 1,
        motion: SnapMotion,
        timing: SnapTiming,
        animatesGeometry: Bool = true
    ) {
        self.startFrame = startFrame
        self.targetFrame = targetFrame
        self.startAlpha = startAlpha
        self.targetAlpha = targetAlpha
        self.motion = motion
        self.timing = timing
        self.animatesGeometry = animatesGeometry
    }

    /// A first appearance with no geometry to animate from.
    static func appear(
        at frame: CGRect,
        alpha: Double = 1,
        timing: SnapTiming = .islandExpand
    ) -> SnapAnimationPlan {
        SnapAnimationPlan(
            startFrame: frame,
            targetFrame: frame,
            startAlpha: 0,
            targetAlpha: alpha,
            motion: .show,
            timing: timing,
            animatesGeometry: false
        )
    }

    /// A transition between two known geometries — `expand`, `collapse`, or `resize`.
    static func resized(_ plan: SnapAnimationPlan) -> SnapAnimationPlan {
        var resized = plan
        resized.motion = .resize
        return resized
    }

    /// The shorter timeline used under Reduce Motion.
    var reduced: SnapAnimationPlan {
        var plan = self
        plan.timing = .reduced
        return plan
    }

    var duration: TimeInterval { SnapAnimationCurve.duration(for: timing) }

    /// Frame and alpha at `elapsed` seconds after the transition started.
    func sample(at elapsed: TimeInterval) -> Sample {
        let progress = SnapAnimationCurve.progress(for: timing, at: elapsed)
        return sample(atProgress: progress)
    }

    /// Frame and alpha at a raw progress value. Split out so an interrupting transition can be
    /// resampled from a mid-flight progress instead of restarting from zero.
    func sample(atProgress progress: Double) -> Sample {
        let eased = progress
        let frame: CGRect
        if animatesGeometry {
            frame = CGRect(
                x: startFrame.minX + (targetFrame.minX - startFrame.minX) * eased,
                y: startFrame.minY + (targetFrame.minY - startFrame.minY) * eased,
                width: startFrame.width + (targetFrame.width - startFrame.width) * eased,
                height: startFrame.height + (targetFrame.height - startFrame.height) * eased
            )
        } else {
            // A transition that does not animate geometry keeps whatever frame it already has —
            // which is the start frame, not the target.
            frame = startFrame
        }

        let alpha = startAlpha + (targetAlpha - startAlpha) * eased
        return Sample(frame: frame, alpha: alpha, progress: progress)
    }

    nonisolated struct Sample: Hashable, Sendable {
        var frame: CGRect
        var alpha: Double
        /// Progress through the timeline. Deliberately not clamped: an underdamped spring goes past
        /// 1 on the way up, and that overshoot is the point. Callers read the frame and the alpha,
        /// not this value, to decide where things are.
        var progress: Double
    }
}
