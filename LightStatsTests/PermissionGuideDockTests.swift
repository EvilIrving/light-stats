//
//  PermissionGuideDockTests.swift
//  Light Stats
//

import XCTest
@testable import Light_Stats

/// Where the card rests beside the System Settings window.
///
/// The rule that matters is not "below by default" but **the card never covers the window**: it is a
/// mouse-opaque panel drawn above the Settings window, so a card that overlaps it swallows both the
/// list the user is asked to drop into and the buttons of the TCC sheet that answers the drop.
final class PermissionGuideDockTests: XCTestCase {

    private let visibleFrame = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    private let cardSize = CGSize(width: 468, height: 104)

    private func dock(beside settings: CGRect) -> PermissionGuideGeometry.Dock {
        PermissionGuideGeometry.dock(cardSize: cardSize, beside: settings, visibleFrame: visibleFrame)
    }

    func testDockSitsBelowTheSettingsWindowRightAligned() {
        let settings = CGRect(x: 200, y: 300, width: 900, height: 600)
        let dock = dock(beside: settings)
        XCTAssertEqual(dock.side, .below)
        XCTAssertEqual(dock.frame.maxY, settings.minY - 16, accuracy: 1e-9, "16pt of air under the window")
        XCTAssertEqual(dock.frame.maxX, settings.maxX - 16, accuracy: 1e-9, "right-aligned with the window")
        XCTAssertEqual(dock.frame.size, cardSize)
    }

    func testDockMovesBesideTheWindowWhenThereIsNoRoomBelow() {
        let settings = CGRect(x: 800, y: 0, width: 700, height: 1000)
        let dock = dock(beside: settings)
        XCTAssertEqual(dock.side, .left, "a window pinned to the bottom has no room for a card under it")
        XCTAssertEqual(dock.frame.maxX, settings.minX - 16, accuracy: 1e-9)
        XCTAssertTrue(visibleFrame.contains(dock.frame), "the card must stay reachable, not hang off the screen")
    }

    func testDockGoesAboveTheWindowWhenNeitherBelowNorEitherSideFits() {
        // Full width, so no band is left or right, and pushed down, so there is none below either.
        let settings = CGRect(x: 0, y: 100, width: 1600, height: 700)
        let dock = dock(beside: settings)
        XCTAssertEqual(dock.side, .above)
        XCTAssertEqual(dock.frame.minY, settings.maxY + 16, accuracy: 1e-9)
        XCTAssertFalse(dock.frame.intersects(settings))
    }

    /// The defect this ordering exists for: a centred Settings window on a laptop display leaves no
    /// room below, and the old fallback clamped the card *onto* the window.
    func testDockFindsAFreeSideForACentredSettingsWindowOnALaptop() {
        let laptop = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let settings = CGRect(x: 270, y: 60, width: 740, height: 625)
        let dock = PermissionGuideGeometry.dock(cardSize: cardSize, beside: settings, visibleFrame: laptop)
        XCTAssertFalse(
            dock.frame.intersects(settings),
            "a card over a centred Settings window covers the list and the TCC sheet's buttons"
        )
        XCTAssertTrue(laptop.contains(dock.frame))
    }

    func testDockNeverCoversAWindowThatLeavesRoomOnOneSideOnly() {
        for origin in [CGFloat(120), 400, 700] {
            let settings = CGRect(x: origin, y: 100, width: 700, height: 800)
            let dock = dock(beside: settings)
            XCTAssertFalse(dock.frame.intersects(settings),
                           "window at x=\(origin): the card found no free side")
            XCTAssertTrue(visibleFrame.contains(dock.frame), "window at x=\(origin): the card left the screen")
        }
    }

    func testDockNeverHangsOffTheScreenEdge() {
        // Runs off the right edge of the display.
        let settings = CGRect(x: 1400, y: 400, width: 900, height: 400)
        let dock = dock(beside: settings)
        XCTAssertTrue(visibleFrame.contains(dock.frame),
                      "a card half off the screen cannot be read or clicked")
        XCTAssertFalse(dock.frame.intersects(settings))
    }

    func testDockClampsRatherThanInvertingOnAnAbsurdlySmallScreen() {
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 120)
        let dock = PermissionGuideGeometry.dock(cardSize: cardSize, beside: tiny, visibleFrame: tiny)
        XCTAssertTrue(dock.frame.width > 0 && dock.frame.height > 0,
                      "a card with no area is a crash waiting for the next frame")
        XCTAssertTrue(tiny.insetBy(dx: -1, dy: -1).contains(dock.frame.origin),
                      "with nowhere free the card is at least clamped into the visible frame")
    }

    // MARK: - Which way the arrow points

    func testEverySideNamesTheDirectionTheListLiesIn() {
        XCTAssertEqual(PermissionGuideDockSide.below.instructionKey, "permission.guide.instruction.above")
        XCTAssertEqual(PermissionGuideDockSide.above.instructionKey, "permission.guide.instruction.below")
        XCTAssertEqual(PermissionGuideDockSide.left.instructionKey, "permission.guide.instruction.beside")
        XCTAssertEqual(PermissionGuideDockSide.right.instructionKey, "permission.guide.instruction.besideLeft")
        XCTAssertEqual(Set(PermissionGuideDockSide.allCases.map(\.instructionKey)).count, 4,
                       "two sides sharing a sentence would point the user the wrong way")
    }

    func testBelowIsPreferredOverEveryOtherSide() {
        XCTAssertEqual(PermissionGuideDockSide.allCases.first, .below,
                       "the preferred order is the order `dock` tries")
    }
}
