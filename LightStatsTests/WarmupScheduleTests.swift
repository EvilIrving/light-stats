//
//  WarmupScheduleTests.swift
//  LightStatsTests
//
//  Created on 2026/06/28.
//
//  Covers the pure scheduling policy for usage-window warmup: the knees of
//  WarmupSchedule.decide (unknown window, far-future, near-fire, expired,
//  dedup against an already-anchored window, and the sleep cap).
//

import XCTest
@testable import Light_Stats

final class WarmupScheduleTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let delay = WarmupSchedule.anchorDelay   // 60s

    func testUnknownWindowWaits() {
        XCTAssertEqual(
            WarmupSchedule.decide(now: now, reset: nil, lastAnchoredReset: nil),
            .waitForWindow
        )
    }

    func testFarFutureResetSleepsCapped() {
        // Reset 4h out → fire point well beyond the cap → sleep exactly the cap.
        let reset = now.addingTimeInterval(4 * 3600)
        XCTAssertEqual(
            WarmupSchedule.decide(now: now, reset: reset, lastAnchoredReset: nil, cap: 60),
            .sleep(60)
        )
    }

    func testNearFireSleepsRemainingDelta() {
        // Reset 30s ago → fire point (reset+60) is 30s out → sleep ~30s (< cap).
        let reset = now.addingTimeInterval(-30)
        XCTAssertEqual(
            WarmupSchedule.decide(now: now, reset: reset, lastAnchoredReset: nil, cap: 60),
            .sleep(30)
        )
    }

    func testExpiredWindowSendsNow() {
        // Reset (delay + 5s) ago → past the fire point → send to anchor a fresh window.
        let reset = now.addingTimeInterval(-(delay + 5))
        XCTAssertEqual(
            WarmupSchedule.decide(now: now, reset: reset, lastAnchoredReset: nil),
            .sendNow
        )
    }

    func testAtFirePointSendsNow() {
        // now == reset + delay exactly → delta 0 → send.
        let reset = now.addingTimeInterval(-delay)
        XCTAssertEqual(
            WarmupSchedule.decide(now: now, reset: reset, lastAnchoredReset: nil),
            .sendNow
        )
    }

    func testAlreadyAnchoredWindowDoesNotResend() {
        // Same reset we already anchored → idle (sleep cap), even though it's past the
        // fire point. Prevents a double-send while the monitor is still showing the
        // stale window before its next refresh.
        let reset = now.addingTimeInterval(-(delay + 120))
        XCTAssertEqual(
            WarmupSchedule.decide(now: now, reset: reset, lastAnchoredReset: reset, cap: 60),
            .sleep(60)
        )
    }

    func testDifferentResetAfterAnchorSchedulesAgain() {
        // A new window (different reset) after we anchored the previous one → schedule.
        let previous = now.addingTimeInterval(-3600)
        let fresh = now.addingTimeInterval(5 * 3600)
        XCTAssertEqual(
            WarmupSchedule.decide(now: now, reset: fresh, lastAnchoredReset: previous, cap: 60),
            .sleep(60)
        )
    }
}
