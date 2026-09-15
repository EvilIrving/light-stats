//
//  SnapAnimationCurveTests.swift
//  Light Stats Tests
//
//  The animation engine, sampled without a display.
//
//  This is the piece Wins cannot test at all — its island animator is a `Timer` plus two closures,
//  so the only way to know whether a transition looks right is to watch it. Here the curve, the
//  duration, the interpolation, and the reduced-motion timeline are all values.
//

import XCTest
@testable import Light_Stats

final class SnapAnimationCurveTests: XCTestCase {

    // MARK: - Curves

    func testLinearCurveIsLinear() {
        let timing = SnapTiming.curve(name: .linear, duration: 1)
        XCTAssertEqual(SnapAnimationCurve.progress(for: timing, at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(SnapAnimationCurve.progress(for: timing, at: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SnapAnimationCurve.progress(for: timing, at: 1), 1, accuracy: 0.0001)
    }

    func testEaseOutStartsFastAndSettlesExactly() {
        let timing = SnapTiming.curve(name: .easeOut, duration: 1)
        XCTAssertEqual(SnapAnimationCurve.progress(for: timing, at: 0), 0, accuracy: 0.0001)
        // Halfway through the clock, well past halfway through the motion.
        XCTAssertGreaterThan(SnapAnimationCurve.progress(for: timing, at: 0.5), 0.8)
        XCTAssertEqual(SnapAnimationCurve.progress(for: timing, at: 1), 1, accuracy: 0.0001)
    }

    func testProgressClampsPastTheEnd() {
        let timing = SnapTiming.curve(name: .linear, duration: 1)
        XCTAssertEqual(SnapAnimationCurve.progress(for: timing, at: 5), 1, accuracy: 0.0001)
        XCTAssertEqual(SnapAnimationCurve.progress(for: timing, at: 0), 0, accuracy: 0.0001)
    }

    func testZeroDurationCurveIsImmediatelyFinished() {
        XCTAssertEqual(SnapAnimationCurve.duration(for: .curve(name: .easeOut, duration: 0)), 0)
        XCTAssertEqual(
            SnapAnimationCurve.progress(for: .curve(name: .easeOut, duration: 0), at: 0),
            1,
            accuracy: 0.0001
        )
    }

    // MARK: - Springs

    func testCriticallyDampedSpringSettlesWithoutOvershooting() {
        let timing = SnapTiming.spring(response: 0.4, dampingFraction: 1)
        XCTAssertEqual(SnapAnimationCurve.progress(for: timing, at: 0), 0, accuracy: 0.0001)

        var previous = 0.0
        for step in 0...60 {
            let value = SnapAnimationCurve.progress(for: timing, at: Double(step) / 60 * 1.5)
            XCTAssertGreaterThanOrEqual(value, previous - 0.0001, "step \(step)")
            XCTAssertLessThanOrEqual(value, 1.0001, "step \(step)")
            previous = value
        }
        XCTAssertEqual(
            SnapAnimationCurve.progress(for: timing, at: 2),
            1,
            accuracy: 0.001
        )
    }

    func testUnderdampedSpringOvershoots() {
        let timing = SnapTiming.spring(response: 0.4, dampingFraction: 0.5)
        var peak = 0.0
        for step in 0...120 {
            peak = max(peak, SnapAnimationCurve.progress(for: timing, at: Double(step) / 120 * 1.2))
        }
        XCTAssertGreaterThan(peak, 1.02, "an underdamped spring should visibly overshoot")
    }

    /// Duration comes from the decay envelope, so a slower spring really is longer and a bouncier
    /// one takes longer to settle than a critically damped one of the same response.
    func testDurationFollowsTheEnvelope() {
        let fast = SnapAnimationCurve.duration(for: .spring(response: 0.2, dampingFraction: 1))
        let slow = SnapAnimationCurve.duration(for: .spring(response: 0.6, dampingFraction: 1))
        XCTAssertLessThan(fast, slow)
        XCTAssertEqual(slow / fast, 3, accuracy: 0.01)

        let bouncy = SnapAnimationCurve.duration(for: .spring(response: 0.4, dampingFraction: 0.6))
        let critical = SnapAnimationCurve.duration(for: .spring(response: 0.4, dampingFraction: 1))
        XCTAssertGreaterThan(bouncy, critical)
    }

    func testDurationIsAlwaysPositive() {
        XCTAssertGreaterThanOrEqual(
            SnapAnimationCurve.duration(for: .spring(response: 0, dampingFraction: 0)),
            0.08
        )
    }

    // MARK: - Plans

    func testPlanInterpolatesTheFrameLinearlyInProgress() {
        let plan = SnapAnimationPlan(
            startFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            targetFrame: CGRect(x: 100, y: 200, width: 300, height: 50),
            motion: .expand,
            timing: .curve(name: .linear, duration: 1)
        )
        let middle = plan.sample(atProgress: 0.5)
        XCTAssertEqual(middle.frame.minX, 50, accuracy: 0.0001)
        XCTAssertEqual(middle.frame.minY, 100, accuracy: 0.0001)
        XCTAssertEqual(middle.frame.width, 200, accuracy: 0.0001)
        XCTAssertEqual(middle.frame.height, 75, accuracy: 0.0001)
    }

    func testHideOnlyPlanKeepsItsFrame() {
        let frame = CGRect(x: 20, y: 30, width: 400, height: 60)
        let plan = SnapAnimationPlan(
            startFrame: frame,
            targetFrame: frame.offsetBy(dx: 500, dy: 500),
            startAlpha: 1,
            targetAlpha: 0,
            motion: .hide,
            timing: .curve(name: .linear, duration: 1),
            animatesGeometry: false
        )
        XCTAssertEqual(plan.sample(atProgress: 0.5).frame, frame)
        XCTAssertEqual(plan.sample(atProgress: 0.5).alpha, 0.5, accuracy: 0.0001)
    }

    func testAppearPlanFadesInWithoutMoving() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        let plan = SnapAnimationPlan.appear(at: frame)
        XCTAssertEqual(plan.motion, .show)
        XCTAssertFalse(plan.animatesGeometry)
        XCTAssertEqual(plan.startAlpha, 0)
        XCTAssertEqual(plan.targetAlpha, 1)
        XCTAssertEqual(plan.sample(atProgress: 0).alpha, 0, accuracy: 0.0001)
    }

    /// Reduce Motion keeps a transition and shortens it. Removing it entirely is the alternative,
    /// and it is the wrong one: an instant jump reads as a glitch.
    func testReducedPlanIsShorterNotAbsent() {
        let plan = SnapAnimationPlan(
            startFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
            targetFrame: CGRect(x: 0, y: 0, width: 200, height: 200),
            motion: .expand,
            timing: .spring(response: 0.6, dampingFraction: 0.7)
        )
        let reduced = plan.reduced
        XCTAssertEqual(reduced.timing, .reduced)
        XCTAssertGreaterThan(reduced.duration, 0)
        XCTAssertLessThan(reduced.duration, plan.duration)
        // The destination is unchanged — only the clock is.
        XCTAssertEqual(reduced.targetFrame, plan.targetFrame)
    }

    /// Progress is deliberately not clamped, and an underdamped spring really does exceed 1. The
    /// driver is what decides when a transition is over — by the clock, so the overshoot peak cannot
    /// be mistaken for the end — and it takes its final sample at exactly 1.
    func testProgressIsNotClampedMidFlightButReachesTheTargetAtTheEnd() {
        let plan = SnapAnimationPlan(
            startFrame: .zero,
            targetFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
            motion: .expand,
            timing: .curve(name: .linear, duration: 0.2)
        )
        XCTAssertEqual(plan.sample(at: 0).progress, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.sample(at: 0.2).progress, 1, accuracy: 0.0001)
        XCTAssertEqual(plan.sample(at: 10).progress, 1, accuracy: 0.0001)
        XCTAssertEqual(plan.sample(atProgress: 1).frame, plan.targetFrame)

        let springy = SnapAnimationPlan(
            startFrame: .zero,
            targetFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
            motion: .expand,
            timing: .spring(response: 0.4, dampingFraction: 0.5)
        )
        var peak = 0.0
        for step in 0...120 {
            peak = max(peak, springy.sample(at: Double(step) / 120 * 1.2).progress)
        }
        XCTAssertGreaterThan(peak, 1.0)
    }

    func testMotionClassification() {
        XCTAssertTrue(SnapMotion.show.startsHidden)
        XCTAssertFalse(SnapMotion.resize.startsHidden)
        XCTAssertTrue(SnapMotion.hide.changesAlpha)
        XCTAssertFalse(SnapMotion.expand.changesAlpha)
    }

    func testSameStateChangeIsAResize() {
        XCTAssertEqual(SnapIslandState.collapsed.motion(to: .open), .expand)
        XCTAssertEqual(SnapIslandState.open.motion(to: .collapsed), .collapse)
        XCTAssertEqual(SnapIslandState.open.motion(to: .open), .resize)
        XCTAssertEqual(SnapIslandState.collapsed.motion(to: .collapsed), .resize)
    }
}
