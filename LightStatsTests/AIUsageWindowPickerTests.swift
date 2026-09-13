//
//  AIUsageWindowPickerTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

final class AIUsageWindowPickerTests: XCTestCase {

    func testEmptyWindowsHaveNoPrimary() {
        XCTAssertNil(AIUsageWindowPicker.mostStrained(in: []))
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: [], expanded: false).isEmpty)
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: [], expanded: true).isEmpty)
    }

    func testSingleWindowStaysOnHeader() {
        let only = window("5h", used: 40)
        XCTAssertEqual(AIUsageWindowPicker.mostStrained(in: [only]), only)
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: [only], expanded: false).isEmpty)
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: [only], expanded: true).isEmpty)
    }

    func testHighestUsedPercentWins() {
        let windows = [
            window("5h", used: 29),
            window("7d", used: 19),
            window(UsageWindowLabel.month.key, used: 9)
        ]
        XCTAssertEqual(AIUsageWindowPicker.mostStrained(in: windows)?.label, "5h")
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

    func testCollapsedMultiWindowHasNoDetailRows() {
        let windows = [
            window("5h", used: 10),
            window("7d", used: 90),
            window(UsageWindowLabel.month.key, used: 20)
        ]
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: windows, expanded: false).isEmpty)
        XCTAssertEqual(AIUsageWindowPicker.mostStrained(in: windows)?.label, "7d")
    }

    func testExpandedListsHeroThenSupportingWindows() {
        let windows = [
            window("5h", used: 10),
            window("7d", used: 90),
            window(UsageWindowLabel.month.key, used: 20)
        ]
        XCTAssertEqual(
            AIUsageWindowPicker.detailWindows(in: windows, expanded: true).map(\.label),
            ["7d", "5h", UsageWindowLabel.month.key]
        )
        XCTAssertEqual(
            AIUsageWindowPicker.supportingWindows(in: windows).map(\.label),
            ["5h", UsageWindowLabel.month.key]
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
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: snapshot.windows, expanded: false).isEmpty)
    }

    private func window(_ label: String, used: Double?) -> UsageWindow {
        UsageWindow(label: label, usedPercent: used, resetsAt: nil)
    }
}
