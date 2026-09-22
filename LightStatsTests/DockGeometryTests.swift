//
//  DockGeometryTests.swift
//  Light Stats Tests
//
//  Where the Dock preview lands.
//
//  Pure arithmetic with real edge cases: an auto-hidden Dock reserves nothing, a preview anchored to
//  an icon near the screen corner has to slide inward instead of running off, and a side Dock needs
//  its panel beside it rather than above it.
//

import XCTest
@testable import Light_Stats

final class DockGeometryTests: XCTestCase {

    /// 1512×982 display, 38pt menu bar, 74pt Dock at the bottom.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let visible = CGRect(x: 0, y: 74, width: 1512, height: 870)

    // MARK: - The Dock's own band

    func testBottomDockBandIsTheReservedStrip() {
        let band = DockGeometry.band(
            screen: screen,
            visibleFrame: visible,
            orientation: .bottom,
            fallbackDockFrame: nil
        )
        XCTAssertEqual(band, CGRect(x: 0, y: 0, width: 1512, height: 74))
    }

    func testSideDockBandUsesTheReservedColumn() {
        let leftVisible = CGRect(x: 80, y: 0, width: 1432, height: 982)
        let band = DockGeometry.band(
            screen: screen,
            visibleFrame: leftVisible,
            orientation: .left,
            fallbackDockFrame: nil
        )
        XCTAssertEqual(band, CGRect(x: 0, y: 0, width: 80, height: 982))

        let rightVisible = CGRect(x: 0, y: 0, width: 1432, height: 982)
        let rightBand = DockGeometry.band(
            screen: screen,
            visibleFrame: rightVisible,
            orientation: .right,
            fallbackDockFrame: nil
        )
        XCTAssertEqual(rightBand, CGRect(x: 1432, y: 0, width: 80, height: 982))
    }

    /// An auto-hidden Dock reserves nothing, so the visible frame is no help and Accessibility's own
    /// rectangle has to win.
    func testAutoHiddenDockFallsBackToTheReportedFrame() {
        let revealed = CGRect(x: 0, y: 4, width: 1512, height: 76)
        let band = DockGeometry.band(
            screen: screen,
            visibleFrame: screen,
            orientation: .bottom,
            fallbackDockFrame: revealed
        )
        XCTAssertEqual(band, revealed)
    }

    func testTopEdgeIsNeverTreatedAsADock() {
        // The reserved space at the top is the menu bar, and a "Dock" there would put the preview
        // under the menu bar.
        let band = DockGeometry.band(
            screen: screen,
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            orientation: .top,
            fallbackDockFrame: nil
        )
        XCTAssertTrue(band.isEmpty)
    }

    // MARK: - Panel placement

    func testBottomDockPanelSitsAboveTheDockAndCentresOnTheIcon() {
        let band = CGRect(x: 0, y: 0, width: 1512, height: 74)
        let anchor = CGRect(x: 700, y: 8, width: 60, height: 60)
        let frame = DockGeometry.previewFrame(
            anchoredTo: anchor,
            band: band,
            panelSize: CGSize(width: 400, height: 200),
            available: visible,
            orientation: .bottom
        )
        XCTAssertEqual(frame.midX, anchor.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, band.maxY + DockGeometry.panelGap, accuracy: 0.5)
        XCTAssertTrue(visible.contains(frame))
    }

    func testPanelSlidesInwardWhenTheIconIsAtTheScreenEdge() {
        let band = CGRect(x: 0, y: 0, width: 1512, height: 74)
        let leftmost = CGRect(x: 2, y: 8, width: 60, height: 60)
        let frame = DockGeometry.previewFrame(
            anchoredTo: leftmost,
            band: band,
            panelSize: CGSize(width: 400, height: 200),
            available: visible,
            orientation: .bottom
        )
        XCTAssertEqual(frame.minX, visible.minX, accuracy: 0.5)
        XCTAssertEqual(frame.maxX, visible.minX + 400, accuracy: 0.5)
    }

    func testPanelSlidesInwardAtTheRightEdgeToo() {
        let band = CGRect(x: 0, y: 0, width: 1512, height: 74)
        let rightmost = CGRect(x: 1500, y: 8, width: 10, height: 60)
        let frame = DockGeometry.previewFrame(
            anchoredTo: rightmost,
            band: band,
            panelSize: CGSize(width: 400, height: 200),
            available: visible,
            orientation: .bottom
        )
        XCTAssertEqual(frame.maxX, visible.maxX, accuracy: 0.5)
    }

    func testSideDockPanelSitsBesideTheBand() {
        let band = CGRect(x: 0, y: 0, width: 80, height: 982)
        let anchor = CGRect(x: 10, y: 400, width: 60, height: 60)
        let frame = DockGeometry.previewFrame(
            anchoredTo: anchor,
            band: band,
            panelSize: CGSize(width: 300, height: 200),
            available: CGRect(x: 80, y: 0, width: 1432, height: 982),
            orientation: .left
        )
        XCTAssertEqual(frame.minX, band.maxX + DockGeometry.panelGap, accuracy: 0.5)
        XCTAssertEqual(frame.midY, anchor.midY, accuracy: 0.5)
    }

    func testPanelIsNotRepositionedAlongThePerpendicularAxis() {
        // A bottom Dock's panel must not be pushed up or down to "fit"; only its x may move.
        let band = CGRect(x: 0, y: 0, width: 1512, height: 74)
        let frame = DockGeometry.previewFrame(
            anchoredTo: nil,
            band: band,
            panelSize: CGSize(width: 400, height: 200),
            available: visible,
            orientation: .bottom
        )
        XCTAssertEqual(frame.minY, band.maxY + DockGeometry.panelGap, accuracy: 0.5)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.5)
    }

    // MARK: - Hover tolerance

    func testHoverSlackMakesTheGestureForgiving() {
        let band = CGRect(x: 0, y: 0, width: 1512, height: 74)
        XCTAssertTrue(DockGeometry.isWithinDock(CGPoint(x: 700, y: 80), band: band, slack: 8))
        XCTAssertFalse(DockGeometry.isWithinDock(CGPoint(x: 700, y: 200), band: band, slack: 8))
    }

    func testAnEmptyBandIsNeverHovered() {
        XCTAssertFalse(DockGeometry.isWithinDock(CGPoint(x: 0, y: 0), band: .zero, slack: 8))
    }

    // MARK: - Orientation

    // MARK: - The appearance motion

    func testThePanelGrowsOutOfTheIconItIsAnchoredTo() {
        let band = DockGeometry.band(screen: screen, visibleFrame: visible, orientation: .bottom, fallbackDockFrame: nil)
        let icon = CGRect(x: 1180, y: band.midY - 35, width: 54, height: 70)
        let final = DockGeometry.previewFrame(
            anchoredTo: icon,
            band: band,
            panelSize: CGSize(width: 900, height: 300),
            available: visible,
            orientation: .bottom
        )

        let start = DockGeometry.appearanceStartFrame(final: final, anchor: icon)

        XCTAssertLessThan(start.width, final.width)
        XCTAssertLessThan(start.height, final.height)
        XCTAssertLessThan(start.maxY, final.maxY, "The panel grows upward")
        XCTAssertGreaterThan(start.minY, band.maxY, "It grows out of the Dock without ever covering it")
        // The icon's centre is the fixed point of the scale, which is what makes the motion read as
        // coming out of the icon rather than shrinking toward the middle of the panel.
        XCTAssertEqual((start.minX - icon.midX) / (final.minX - icon.midX), 0.94, accuracy: 0.0001)
        XCTAssertEqual((start.midY - icon.midY) / (final.midY - icon.midY), 0.94, accuracy: 0.0001)
    }

    func testADegenerateGeometryStillReturnsThePanelWhereItBelongs() {
        let final = CGRect(x: 400, y: 94, width: 900, height: 300)
        XCTAssertEqual(DockGeometry.appearanceStartFrame(final: final, anchor: .zero), final,
                       "A Dock item with no frame must not scale the panel into nothing")
        XCTAssertEqual(DockGeometry.appearanceStartFrame(final: .zero, anchor: CGRect(x: 0, y: 0, width: 10, height: 10)), .zero)
    }

    func testOrientationComesFromTheDockPreferences() {
        let suite = "com.lightstats.tests.dock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }

        XCTAssertEqual(DockHoverMonitorService.dockOrientation(defaults: defaults ?? .standard), .bottom)

        defaults?.set("left", forKey: "orientation")
        XCTAssertEqual(DockHoverMonitorService.dockOrientation(defaults: defaults ?? .standard), .left)
    }

    func testUnknownOrientationFallsBackToTheBottom() {
        let suite = "com.lightstats.tests.dock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }

        defaults?.set("diagonal", forKey: "orientation")
        XCTAssertEqual(DockHoverMonitorService.dockOrientation(defaults: defaults ?? .standard), .bottom)
    }
}
