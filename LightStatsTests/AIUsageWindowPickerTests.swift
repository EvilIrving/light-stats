//
//  AIUsageWindowPickerTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

final class AIUsageWindowPickerTests: XCTestCase {

    func testEmptyWindowsHaveNoPrimary() {
        XCTAssertNil(AIUsageWindowPicker.mostStrained(in: []))
        XCTAssertTrue(AIUsageWindowPicker.visibleWindows(in: [], expanded: false).isEmpty)
    }

    func testSingleWindowIsUnchanged() {
        let only = window("5h", used: 40)
        XCTAssertEqual(AIUsageWindowPicker.mostStrained(in: [only]), only)
        XCTAssertEqual(
            AIUsageWindowPicker.visibleWindows(in: [only], expanded: false),
            [only]
        )
        XCTAssertEqual(
            AIUsageWindowPicker.visibleWindows(in: [only], expanded: true),
            [only]
        )
    }

    func testHighestUsedPercentWins() {
        let windows = [
            window("5h", used: 29),
            window("7d", used: 19),
            window(UsageWindowLabel.month.key, used: 9)
        ]
        XCTAssertEqual(AIUsageWindowPicker.mostStrained(in: windows)?.label, "5h")
        XCTAssertEqual(
            AIUsageWindowPicker.visibleWindows(in: windows, expanded: false).map(\.label),
            ["5h"]
        )
    }

    func testLowestRemainingIsMostStrained() {
        let windows = [
            window("5h", used: 12),
            window("7d", used: 88),
            window("Month", used: 40)
        ]
        XCTAssertEqual(AIUsageWindowPicker.mostStrained(in: windows)?.label, "7d")
    }

    func testTieKeepsEarlierWindow() {
        let windows = [
            window("5h", used: 50),
            window("7d", used: 50)
        ]
        XCTAssertEqual(AIUsageWindowPicker.mostStrained(in: windows)?.label, "5h")
    }

    func testNilPercentIsLeastStrained() {
        let windows = [
            window("5h", used: nil),
            window("7d", used: 8),
            window("Month", used: nil)
        ]
        XCTAssertEqual(AIUsageWindowPicker.mostStrained(in: windows)?.label, "7d")
    }

    func testAllNilPercentKeepsFirst() {
        let windows = [
            window("5h", used: nil),
            window("7d", used: nil)
        ]
        XCTAssertEqual(AIUsageWindowPicker.mostStrained(in: windows)?.label, "5h")
    }

    func testExpandedKeepsProviderOrder() {
        let windows = [
            window("5h", used: 10),
            window("7d", used: 90),
            window(UsageWindowLabel.month.key, used: 20)
        ]
        XCTAssertEqual(
            AIUsageWindowPicker.visibleWindows(in: windows, expanded: true).map(\.label),
            ["5h", "7d", UsageWindowLabel.month.key]
        )
    }

    func testBalanceSnapshotDoesNotInventAWindow() {
        let snapshot = ProviderUsageSnapshot(
            provider: .deepseek,
            windows: [],
            balance: UsageBalance(
                currency: "CNY",
                total: "235.91",
                granted: nil,
                toppedUp: nil,
                isAvailable: true
            ),
            fetchedAt: Date()
        )
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertNil(AIUsageWindowPicker.mostStrained(in: snapshot.windows))
        XCTAssertEqual(
            AIUsageWindowPicker.visibleWindows(in: snapshot.windows, expanded: false),
            []
        )
    }

    private func window(_ label: String, used: Double?) -> UsageWindow {
        UsageWindow(label: label, usedPercent: used, resetsAt: nil)
    }
}
