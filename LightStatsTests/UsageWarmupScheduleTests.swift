//
//  UsageWarmupScheduleTests.swift
//  Light Stats Tests
//
//  Locks the reset-aware warmup schedule so the app does not drift back to
//  fixed-interval mid-window sends.
//

import XCTest
@testable import Light_Stats

@MainActor
final class UsageWarmupScheduleTests: XCTestCase {

    func testFutureResetSchedulesAfterDelay() {
        let now = Date(timeIntervalSince1970: 1_000)
        let reset = Date(timeIntervalSince1970: 2_000)
        let snapshot = snapshot(reset: reset)

        let fireDate = UsageWarmupManager.nextFireDate(
            from: snapshot,
            now: now,
            resetDelay: 60,
            lastSentReset: nil
        )

        XCTAssertEqual(fireDate, reset.addingTimeInterval(60))
    }

    func testPastResetFiresImmediately() {
        let now = Date(timeIntervalSince1970: 2_000)
        let reset = Date(timeIntervalSince1970: 1_000)
        let snapshot = snapshot(reset: reset)

        let fireDate = UsageWarmupManager.nextFireDate(
            from: snapshot,
            now: now,
            resetDelay: 60,
            lastSentReset: nil
        )

        XCTAssertEqual(fireDate, now)
    }

    func testAlreadySentResetDoesNotRepeat() {
        let now = Date(timeIntervalSince1970: 2_000)
        let reset = Date(timeIntervalSince1970: 1_000)
        let snapshot = snapshot(reset: reset)

        let fireDate = UsageWarmupManager.nextFireDate(
            from: snapshot,
            now: now,
            resetDelay: 60,
            lastSentReset: reset
        )

        XCTAssertNil(fireDate)
    }

    func testMissingResetDoesNotBlindFire() {
        let now = Date(timeIntervalSince1970: 2_000)
        let snapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [UsageWindow(label: "5h", usedPercent: 12, resetsAt: nil)],
            fetchedAt: now
        )

        let fireDate = UsageWarmupManager.nextFireDate(
            from: snapshot,
            now: now,
            resetDelay: 60,
            lastSentReset: nil
        )

        XCTAssertNil(fireDate)
    }

    private func snapshot(reset: Date) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .codex,
            windows: [
                UsageWindow(label: "5h", usedPercent: 12, resetsAt: reset),
                UsageWindow(label: "7d", usedPercent: 8, resetsAt: reset.addingTimeInterval(7 * 24 * 3600)),
            ],
            fetchedAt: reset
        )
    }
}
