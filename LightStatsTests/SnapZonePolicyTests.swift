//
//  SnapZonePolicyTests.swift
//  Light Stats Tests
//
//  The drag-to-edge decision. Every branch here is a branch a user can feel: an edge that fires too
//  eagerly is a window that jumps when they did not mean it, and an edge that misses is a feature
//  that does not work.
//

import XCTest
@testable import Light_Stats

final class SnapZonePolicyTests: XCTestCase {

    /// 1512×982 display, 38pt menu bar. The top boundary for dragging is the visible top, and the
    /// other three are the physical edges.
    private let screen = SnapScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 944)
    )

    private var configuration: SnapZoneConfiguration { .default }

    private func zone(at point: CGPoint, configuration: SnapZoneConfiguration? = nil) -> SnapZoneResult {
        SnapZonePolicy.result(
            pointer: point,
            screen: screen,
            configuration: configuration ?? self.configuration
        )
    }

    // MARK: - Edges

    func testLeftEdgeArmsTheLeftHalf() {
        let result = zone(at: CGPoint(x: 4, y: 400))
        XCTAssertEqual(result.zone, .left)
        XCTAssertEqual(result.target, .region(.leftHalf))
        XCTAssertFalse(result.isIslandActive)
    }

    func testRightEdgeArmsTheRightHalf() {
        XCTAssertEqual(zone(at: CGPoint(x: 1508, y: 400)).zone, .right)
    }

    func testBottomEdgeOffersTheCenterThird() {
        XCTAssertEqual(zone(at: CGPoint(x: 700, y: 978)).zone, .centerThird)
    }

    func testMiddleOfTheScreenArmsNothing() {
        XCTAssertFalse(zone(at: CGPoint(x: 700, y: 500)).isActive)
    }

    // MARK: - Top edge

    /// The top boundary is the *visible* top, not the physical one: a window cannot be pushed into
    /// the menu bar, so the gesture has to complete where the window stops.
    func testTopEdgeArmsFromTheVisibleTopNotThePhysicalEdge() {
        let result = zone(at: CGPoint(x: 700, y: 40))
        XCTAssertTrue(result.isIslandActive)
        XCTAssertEqual(result.zone, .top)
    }

    func testTopEdgeTurnsIntoTheIslandOnlyInsideTheCentreBand() {
        let offCentre = zone(at: CGPoint(x: 100, y: 40))
        XCTAssertFalse(offCentre.isIslandActive)
        XCTAssertEqual(offCentre.zone, .top)
    }

    func testTopEdgeWithMaximizeModeTargetsTheWholeScreen() {
        var configuration = SnapZoneConfiguration.default
        configuration.topEdgeMode = .maximize
        let result = zone(at: CGPoint(x: 700, y: 40), configuration: configuration)
        XCTAssertFalse(result.isIslandActive)
        XCTAssertEqual(result.zone, .top)
        XCTAssertEqual(result.target, .region(.full))
    }

    func testTurningOffTheTopEdgeLeavesTheIndependentCornerSwitchWorking() {
        var configuration = SnapZoneConfiguration.default
        configuration.topEdgeMode = .disabled
        XCTAssertEqual(zone(at: CGPoint(x: 700, y: 40), configuration: configuration).zone, .none)
        XCTAssertEqual(zone(at: CGPoint(x: 4, y: 40), configuration: configuration).zone, .topLeft)
    }

    // MARK: - Corners

    func testCornersWinOverEdgesWhenBothAreInReach() {
        XCTAssertEqual(zone(at: CGPoint(x: 4, y: 40)).zone, .topLeft)
        XCTAssertEqual(zone(at: CGPoint(x: 1508, y: 40)).zone, .topRight)
        XCTAssertEqual(zone(at: CGPoint(x: 4, y: 978)).zone, .bottomLeft)
        XCTAssertEqual(zone(at: CGPoint(x: 1508, y: 978)).zone, .bottomRight)
    }

    func testCornersDoNotConsumeLargePartsOfTheTopEdge() {
        XCTAssertEqual(zone(at: CGPoint(x: 30, y: 40)).zone, .topLeft)
        XCTAssertEqual(zone(at: CGPoint(x: 240, y: 40)).zone, .top)
        XCTAssertEqual(zone(at: CGPoint(x: 400, y: 40)).zone, .top)
    }

    func testCornersCanBeTurnedOff() {
        var configuration = SnapZoneConfiguration.default
        configuration.cornersEnabled = false
        XCTAssertEqual(zone(at: CGPoint(x: 4, y: 40), configuration: configuration).zone, .top)
        XCTAssertEqual(zone(at: CGPoint(x: 4, y: 978), configuration: configuration).zone, .lowerHalf)
        // The side edge that was not part of a corner still works.
        XCTAssertEqual(zone(at: CGPoint(x: 4, y: 500), configuration: configuration).zone, .left)
    }

    func testEdgesCanBeTurnedOff() {
        var configuration = SnapZoneConfiguration.default
        configuration.edgesEnabled = false
        XCTAssertEqual(zone(at: CGPoint(x: 4, y: 400), configuration: configuration).zone, .none)
        XCTAssertEqual(zone(at: CGPoint(x: 1508, y: 400), configuration: configuration).zone, .none)
        // The top edge is not one of the side edges, so it still works.
        XCTAssertTrue(zone(at: CGPoint(x: 700, y: 40), configuration: configuration).isIslandActive)
    }

    func testBothSideEdgesOfferUpperMiddleAndLowerForms() {
        for x in [CGFloat(4), CGFloat(1508)] {
            XCTAssertEqual(zone(at: CGPoint(x: x, y: 130)).target, .region(.topHalf))
            XCTAssertEqual(zone(at: CGPoint(x: x, y: 500)).target, .region(x < 100 ? .leftHalf : .rightHalf))
            XCTAssertEqual(zone(at: CGPoint(x: x, y: 900)).target, .region(.bottomHalf))
        }
    }

    func testBottomBandsExposeAllFiveThirdsDestinations() {
        let expected: [SnapZone] = [.leftThird, .leftTwoThirds, .centerThird, .rightTwoThirds, .rightThird]
        for (index, expectedZone) in expected.enumerated() {
            let result = zone(at: CGPoint(x: (CGFloat(index) + 0.5) * screen.frame.width / 5, y: 978))
            XCTAssertEqual(result.zone, expectedZone)
            XCTAssertEqual(result.target, expectedZone.normalizedRect.map { .region($0) })
        }
    }

    func testAdjacentBandsHaveAStableBoundaryWithoutDelayingADeliberateCrossing() {
        let boundary = screen.visibleFrame.minY + screen.visibleFrame.height * 0.18
        let previous = zone(at: CGPoint(x: 4, y: boundary - 2))
        XCTAssertEqual(previous.zone, .upperHalf)
        let near = SnapZonePolicy.result(pointer: CGPoint(x: 4, y: boundary + 2), screen: screen,
                                         configuration: configuration, previous: previous)
        XCTAssertEqual(near.zone, .upperHalf, "A small pointer wobble must not flicker between two layouts")
        let crossed = SnapZonePolicy.result(pointer: CGPoint(x: 4, y: boundary + 12), screen: screen,
                                            configuration: configuration, previous: previous)
        XCTAssertEqual(crossed.zone, .left)
    }

    func testARealCornerOverridesTheSideBandImmediately() {
        let previous = zone(at: CGPoint(x: 4, y: 130))
        XCTAssertEqual(SnapZonePolicy.result(pointer: CGPoint(x: 4, y: 40), screen: screen,
                                             configuration: configuration, previous: previous).zone, .topLeft)
    }

    func testEdgeFormsTranslateToAnotherDisplayWithoutChangingTheirMeaning() {
        let translated = SnapScreenGeometry(
            frame: screen.frame.offsetBy(dx: -1600, dy: -1000),
            visibleFrame: screen.visibleFrame.offsetBy(dx: -1600, dy: -1000)
        )
        let points = [CGPoint(x: 4, y: 130), CGPoint(x: 1508, y: 900), CGPoint(x: 450, y: 978)]
        for point in points {
            let target = SnapZonePolicy.result(pointer: CGPoint(x: point.x - 1600, y: point.y - 1000),
                                               screen: translated, configuration: configuration).target
            XCTAssertEqual(target, zone(at: point).target)
        }
    }

    // MARK: - Which display

    func testAPointerWellOutsideTheDisplayArmsNothing() {
        XCTAssertFalse(zone(at: CGPoint(x: -600, y: 400)).isActive)
        XCTAssertFalse(zone(at: CGPoint(x: 2_000, y: 400)).isActive)
    }

    /// Overshooting past an edge is expected — the pointer is allowed into the Dock and over the
    /// menu bar — so a small overshoot still counts.
    func testSmallOvershootStillCounts() {
        XCTAssertEqual(zone(at: CGPoint(x: -8, y: 400)).zone, .left)
    }

    func testDisabledConfigurationNeverArms() {
        XCTAssertFalse(zone(at: CGPoint(x: 4, y: 400), configuration: .disabled).isActive)
        XCTAssertFalse(zone(at: CGPoint(x: 4, y: 40), configuration: .disabled).isActive)
    }

    func testEveryZoneMapsToATile() {
        XCTAssertEqual(SnapZone.left.normalizedRect, .leftHalf)
        XCTAssertEqual(SnapZone.right.normalizedRect, .rightHalf)
        XCTAssertEqual(SnapZone.bottom.normalizedRect, .bottomHalf)
        // The top edge means "fill", not "top half" — that is the whole point of the gesture.
        XCTAssertEqual(SnapZone.top.normalizedRect, .full)
        XCTAssertEqual(SnapZone.topLeft.normalizedRect, .topLeftQuarter)
        XCTAssertNil(SnapZone.none.normalizedRect)
    }

    func testZoneToActionMapping() {
        XCTAssertEqual(WindowSnapAction.forZone(.left), .leftHalf)
        XCTAssertEqual(WindowSnapAction.forZone(.topRight), .topRight)
        XCTAssertNil(WindowSnapAction.forZone(.none))
    }
}
