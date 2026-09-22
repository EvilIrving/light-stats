//
//  SnapAnimationDriver.swift
//  Light Stats
//

import AppKit
import OSLog

/// Drives a `SnapAnimationPlan` frame by frame on the main run loop.
///
/// A `Timer`, not `NSAnimationContext`, for one reason: the
/// intermediate frames have to be readable, because the island changes its corner radii, its shadow
/// progress, and its content layout on the same timeline that moves it. An API that only offers a
/// start value and an end value cannot do that, and cannot be interrupted mid-flight.
///
/// The timer is a little faster than the display refresh, and every tick is computed from an
/// absolute start time rather than accumulated, so a delayed tick produces the right frame instead
/// of a permanently lagging animation.
@MainActor
final class SnapAnimationDriver {

    private var timer: Timer?
    private var plan: SnapAnimationPlan?
    private var startedAt: TimeInterval = 0
    private var onUpdate: ((SnapAnimationPlan.Sample) -> Void)?
    private var onFinish: (() -> Void)?
    private var generation: UInt64 = 0

    /// 120 Hz, in common modes so the animation keeps running while a menu is tracking or a drag is
    /// in progress — the two moments it actually matters.
    private let tickInterval: TimeInterval = 1.0 / 120.0

    var isRunning: Bool { timer != nil }

    /// Starts (or restarts) the animation. The previous one is abandoned, not finished.
    ///
    /// `reduceMotion` swaps in a shorter timeline rather than removing the transition: an instant
    /// jump reads as a glitch, while a short one still reads as a deliberate movement.
    func run(
        plan: SnapAnimationPlan,
        reduceMotion: Bool? = nil,
        onUpdate: @escaping (SnapAnimationPlan.Sample) -> Void,
        onFinish: (() -> Void)? = nil
    ) {
        cancel()
        generation += 1
        let currentGeneration = generation

        let effective = (reduceMotion ?? ReduceMotionPreference.isEnabled) ? plan.reduced : plan
        self.plan = effective
        self.onUpdate = onUpdate
        self.onFinish = onFinish
        startedAt = ProcessInfo.processInfo.systemUptime

        // A zero-length plan (reduce motion with no geometry change) still delivers one sample so
        // the caller's end state is applied exactly once.
        let duration = effective.duration
        if duration <= 0 {
            onUpdate(effective.sample(atProgress: 1))
            finish(generation: currentGeneration)
            return
        }

        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(generation: currentGeneration)
            }
        }
        timer.tolerance = tickInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        generation += 1
        timer?.invalidate()
        timer = nil
        plan = nil
        onUpdate = nil
        onFinish = nil
    }

    private func tick(generation: UInt64) {
        guard generation == self.generation, let plan else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let finished = elapsed >= plan.duration

        // A spring that overshoots crosses 1.0 on the way up. Finishing there — the obvious reading
        // of "the progress reached the target" — would stop the transition at the overshoot peak and
        // leave the panel a few percent too large or too small forever. The clock decides; the final
        // sample is taken at exactly 1 so the end state is the target and not "the target ± epsilon".
        onUpdate?(finished ? plan.sample(atProgress: 1) : plan.sample(at: elapsed))
        if finished {
            finish(generation: generation)
        }
    }

    private func finish(generation: UInt64) {
        guard generation == self.generation else { return }
        let callback = onFinish
        timer?.invalidate()
        timer = nil
        plan = nil
        onUpdate = nil
        onFinish = nil
        callback?()
    }
}
