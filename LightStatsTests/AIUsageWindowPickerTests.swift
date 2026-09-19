//
//  AIUsageWindowPickerTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

final class AIUsageWindowPickerTests: XCTestCase {

    func testEmptyWindowsHaveNoPrimary() {
        XCTAssertNil(AIUsageWindowPicker.nearestReset(in: []))
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: [], expanded: false).isEmpty)
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: [], expanded: true).isEmpty)
    }

    func testSingleWindowStaysOnHeader() {
        let only = window("5h", used: 40, resetsIn: 3600)
        XCTAssertEqual(AIUsageWindowPicker.nearestReset(in: [only]), only)
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: [only], expanded: false).isEmpty)
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: [only], expanded: true).isEmpty)
    }

    func testNearestResetWinsOverHigherUsage() {
        let windows = [
            window("5h", used: 10, resetsIn: 20 * 60),
            window("7d", used: 88, resetsIn: 3 * 86400)
        ]
        XCTAssertEqual(AIUsageWindowPicker.nearestReset(in: windows)?.label, "5h")
    }

    func testNearestResetWinsAcrossProviderOrder() {
        let windows = [
            window(UsageWindowLabel.month.key, used: 9, resetsIn: 17 * 86400),
            window("5h", used: 12, resetsIn: 90 * 60),
            window("7d", used: 29, resetsIn: 4 * 86400)
        ]
        XCTAssertEqual(AIUsageWindowPicker.nearestReset(in: windows)?.label, "5h")
    }

    func testTieKeepsEarlierWindow() {
        let windows = [
            window("5h", used: 50, resetsIn: 7200),
            window("7d", used: 50, resetsIn: 7200)
        ]
        XCTAssertEqual(AIUsageWindowPicker.nearestReset(in: windows)?.label, "5h")
    }

    func testUnknownResetTimeNeverWinsOverADatedWindow() {
        let windows = [
            window("Credits", used: 70, resetsIn: nil),
            window("5h", used: 3, resetsIn: 6 * 3600)
        ]
        XCTAssertEqual(AIUsageWindowPicker.nearestReset(in: windows)?.label, "5h")
    }

    func testHeaderFollowsTheWindowThatResetsFirst() {
        let windows = [
            window("5h", used: 95, resetsIn: 5 * 86400),
            window("7d", used: 5, resetsIn: 30 * 60)
        ]
        XCTAssertEqual(AIUsageWindowPicker.nearestReset(in: windows)?.label, "7d")
    }

    func testAllUnknownResetTimesKeepProviderOrder() {
        let windows = [
            window("5h", used: 70, resetsIn: nil),
            window("7d", used: 20, resetsIn: nil)
        ]
        XCTAssertEqual(AIUsageWindowPicker.nearestReset(in: windows)?.label, "5h")
    }

    func testCollapsedMultiWindowHasNoDetailRows() {
        let windows = [
            window("5h", used: 10, resetsIn: 3600),
            window("7d", used: 90, resetsIn: 5 * 86400),
            window(UsageWindowLabel.month.key, used: 20, resetsIn: 20 * 86400)
        ]
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: windows, expanded: false).isEmpty)
        XCTAssertEqual(AIUsageWindowPicker.nearestReset(in: windows)?.label, "5h")
    }

    func testExpandedListsEveryWindowInProviderOrder() {
        let windows = [
            window("5h", used: 10, resetsIn: 3600),
            window("7d", used: 90, resetsIn: 5 * 86400),
            window(UsageWindowLabel.month.key, used: 20, resetsIn: 20 * 86400)
        ]
        XCTAssertEqual(
            AIUsageWindowPicker.detailWindows(in: windows, expanded: true).map(\.label),
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
        XCTAssertNil(AIUsageWindowPicker.nearestReset(in: snapshot.windows))
        XCTAssertTrue(AIUsageWindowPicker.detailWindows(in: snapshot.windows, expanded: false).isEmpty)
    }

    // MARK: - Helpers

    /// Fixed base date: the picker compares reset dates, so ties must be exact
    /// rather than microseconds apart.
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func window(_ label: String, used: Double?, resetsIn: TimeInterval?) -> UsageWindow {
        UsageWindow(
            label: label,
            usedPercent: used,
            resetsAt: resetsIn.map { base.addingTimeInterval($0) }
        )
    }
}
