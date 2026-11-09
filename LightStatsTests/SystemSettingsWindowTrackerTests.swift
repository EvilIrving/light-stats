//
//  SystemSettingsWindowTrackerTests.swift
//  Light Stats
//

import XCTest
@testable import Light_Stats

/// Which window the guide docks beside, and when it counts as having stopped moving.
///
/// Both halves are values so neither needs a window server: the live tracker only feeds these
/// functions a `CGWindowList` snapshot. Getting them wrong shows up as a card that docks to the
/// Go-to-folder sheet, or that jumps once more after the user has already started dragging.
final class SystemSettingsWindowTrackerTests: XCTestCase {

    // MARK: - Stabilisation

    func testIdenticalSamplesAreStable() {
        let frame = CGRect(x: 120, y: 80, width: 900, height: 640)
        XCTAssertTrue(SystemSettingsWindowTracker.isStable(previous: frame, current: frame))
    }

    func testSubPixelJitterCountsAsStable() {
        let first = CGRect(x: 120.2, y: 80.4, width: 900.0, height: 640.0)
        let second = CGRect(x: 120.4, y: 80.2, width: 900.2, height: 639.8)
        XCTAssertTrue(
            SystemSettingsWindowTracker.isStable(previous: first, current: second),
            "a window mid-animation lands on sub-point positions; waiting for bit equality would burn the budget"
        )
    }

    func testAWindowThatIsStillGrowingIsNotStable() {
        let first = CGRect(x: 120, y: 80, width: 400, height: 300)
        let second = CGRect(x: 120, y: 80, width: 900, height: 640)
        XCTAssertFalse(
            SystemSettingsWindowTracker.isStable(previous: first, current: second),
            "System Settings opens at a default size and resizes as the pane loads; docking to that is a wrong answer"
        )
    }

    func testATwoPointMoveIsNotStable() {
        let first = CGRect(x: 120, y: 80, width: 900, height: 640)
        let second = first.offsetBy(dx: 2, dy: 0)
        XCTAssertFalse(SystemSettingsWindowTracker.isStable(previous: first, current: second))
    }

    // MARK: - Which window

    private func candidate(
        _ owner: String,
        processID: pid_t = 0,
        layer: Int = 0,
        size: CGSize = CGSize(width: 900, height: 640),
        origin: CGPoint = .zero
    ) -> SystemSettingsWindowTracker.Candidate {
        SystemSettingsWindowTracker.Candidate(
            ownerName: owner,
            ownerPID: processID,
            layer: layer,
            bounds: CGRect(origin: origin, size: size)
        )
    }

    func testTheLargestSettingsWindowWins() {
        let sheet = candidate("System Settings", size: CGSize(width: 420, height: 260), origin: CGPoint(x: 300, y: 300))
        let main = candidate("System Settings", size: CGSize(width: 900, height: 640), origin: CGPoint(x: 120, y: 80))
        XCTAssertEqual(SystemSettingsWindowTracker.settingsBounds(from: [sheet, main]),
                       CGRect(x: 120, y: 80, width: 900, height: 640))
    }

    func testALocalizedOwnerNameStillMatchesThroughTheProcessIdentifier() {
        let localized = candidate("系统设置", processID: 4321, size: CGSize(width: 740, height: 625))
        XCTAssertEqual(
            SystemSettingsWindowTracker.settingsBounds(from: [localized], settingsProcessID: 4321),
            CGRect(x: 0, y: 0, width: 740, height: 625),
            "kCGWindowOwnerName is localized — a name-only match finds nothing on a non-English system"
        )
    }

    func testTheProcessIdentifierAlsoRejectsLookalikes() {
        let preview = candidate("System Settings Preview", processID: 99)
        XCTAssertNil(
            SystemSettingsWindowTracker.settingsBounds(from: [preview], settingsProcessID: 4321),
            "a window that merely mentions System Settings is not the System Settings window"
        )
    }

    func testAnotherApplicationIsNeverTheDockTarget() {
        let other = candidate("Finder", size: CGSize(width: 1600, height: 1000))
        XCTAssertNil(SystemSettingsWindowTracker.settingsBounds(from: [other]))
    }

    func testAMenuBarExtraOfSystemSettingsIsNotTheDockTarget() {
        let menuExtra = candidate("System Settings", layer: 25, size: CGSize(width: 340, height: 40))
        XCTAssertNil(SystemSettingsWindowTracker.settingsBounds(from: [menuExtra]))
    }

    func testATooltipSizedWindowIsNotTheDockTarget() {
        let tooltip = candidate("System Settings", size: CGSize(width: 240, height: 120))
        XCTAssertNil(SystemSettingsWindowTracker.settingsBounds(from: [tooltip]))
    }

    func testTheFrameIsReportedUnrounded() {
        let fractional = candidate("System Settings", size: CGSize(width: 900.4, height: 640.6),
                                   origin: CGPoint(x: 120.25, y: 80.75))
        let bounds = SystemSettingsWindowTracker.settingsBounds(from: [fractional])
        XCTAssertEqual(bounds?.origin.x, 120.25)
        XCTAssertEqual(bounds?.width, 900.4,
                       "rounding is for comparing samples only; a dock target that was moved is a visible bug")
    }

    func testAnEmptyWindowListHasNoDockTarget() {
        XCTAssertNil(SystemSettingsWindowTracker.settingsBounds(from: []))
    }
}
