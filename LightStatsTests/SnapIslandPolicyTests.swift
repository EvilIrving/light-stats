//
//  SnapIslandPolicyTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

final class SnapIslandPolicyTests: XCTestCase {
    private let screenRect = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let screen = SnapScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 944)
    )
    private let configuration = SnapIslandConfiguration.default

    func testTheIslandHangsFromTheScreenTop() {
        for state in [SnapIslandState.collapsed, .open] {
            let frame = SnapIslandPolicy.frame(for: state, in: screenRect, configuration: configuration)
            XCTAssertEqual(frame.minY, screenRect.minY)
            XCTAssertEqual(frame.midX, screenRect.midX)
        }
    }

    func testCollapsedStripIsCompactAndExpansionStaysTopCentered() {
        let collapsed = SnapIslandPolicy.frame(for: .collapsed, in: screenRect, configuration: configuration)
        let expanded = SnapIslandPolicy.frame(for: .open, in: screenRect, configuration: configuration)
        XCTAssertLessThanOrEqual(collapsed.width, 184)
        XCTAssertLessThanOrEqual(collapsed.height, 32)
        XCTAssertGreaterThan(expanded.width, collapsed.width)
        XCTAssertGreaterThan(expanded.height, collapsed.height)
        XCTAssertEqual(expanded.midX, collapsed.midX)
        XCTAssertEqual(expanded.minY, collapsed.minY)
    }

    func testIslandOnAnUpperDisplayStaysOnThatDisplay() {
        let upper = CGRect(x: 240, y: -1080, width: 1920, height: 1080)
        let frame = SnapIslandPolicy.frame(for: .open, in: upper, configuration: configuration)
        XCTAssertEqual(frame.minY, upper.minY)
        XCTAssertEqual(frame.midX, upper.midX)
    }

    func testTheIslandNeverWiderThanItsMaximum() {
        let ultrawide = CGRect(x: 0, y: 0, width: 5120, height: 1440)
        XCTAssertEqual(SnapIslandPolicy.frame(for: .open, in: ultrawide, configuration: configuration).width, configuration.maximumWidth)
    }

    func testCentredTopEdgeActivates() {
        XCTAssertTrue(SnapIslandPolicy.isActivated(pointer: CGPoint(x: 756, y: 40), screen: screen,
                                                   configuration: configuration, zoneConfiguration: .default))
    }

    func testOffCentreAndBelowTopDoNotActivate() {
        for point in [CGPoint(x: 100, y: 40), CGPoint(x: 756, y: 120)] {
            XCTAssertFalse(SnapIslandPolicy.isActivated(pointer: point, screen: screen,
                                                        configuration: configuration, zoneConfiguration: .default))
        }
    }

    func testIslandModeOffDisablesActivation() {
        var zones = SnapZoneConfiguration.default
        zones.topEdgeMode = .maximize
        XCTAssertFalse(SnapIslandPolicy.isActivated(pointer: CGPoint(x: 756, y: 40), screen: screen,
                                                    configuration: configuration, zoneConfiguration: zones))
    }

    func testEveryLayoutIsDirectlyDroppableWithoutSelectingALayoutFirst() {
        let layouts = SnapConfiguration.default.islandLayouts
        let size = SnapLayoutProjection.referenceSize
        let height = SnapIslandLayout.preferredHeight(layoutCount: layouts.count, width: 560, sourceSize: size)
        let panel = CGRect(x: 0, y: 0, width: 560, height: height)
        let tiles = SnapIslandLayout.tiles(layouts: layouts, panel: panel, margins: .zero)
        XCTAssertEqual(tiles.count, layouts.reduce(0) { $0 + $1.segments.count })
        for tile in tiles {
            let hit = SnapIslandLayout.hit(at: CGPoint(x: tile.frame.midX, y: tile.frame.midY),
                                          layouts: layouts, panel: panel, margins: .zero)
            XCTAssertEqual(hit?.layoutID, tile.layoutID)
            XCTAssertEqual(hit?.segment.id, tile.segment.id)
            XCTAssertEqual(hit?.segment.rect, tile.segment.rect)
        }
    }

    func testDefaultLayoutsShareOneAlignedRow() {
        let layouts = SnapConfiguration.default.islandLayouts
        let panel = CGRect(x: 0, y: 0, width: 560, height: 110)
        let frames = SnapIslandLayout.layoutFrames(layouts: layouts, panel: panel)
        XCTAssertEqual(frames.count, 4)
        for frame in frames {
            XCTAssertEqual(frame.frame.minY, frames[0].frame.minY)
            XCTAssertEqual(frame.frame.height, frames[0].frame.height)
            XCTAssertEqual(frame.frame.width, frames[0].frame.width)
        }
    }

    func testTheGapBetweenLayoutsAndBetweenSegmentsCancelsTheDrop() {
        let layouts = SnapConfiguration.default.islandLayouts
        let panel = CGRect(x: 0, y: 0, width: 560, height: 110)
        let frames = SnapIslandLayout.layoutFrames(layouts: layouts, panel: panel)
        let gap = CGPoint(x: (frames[0].frame.maxX + frames[1].frame.minX) / 2, y: frames[0].frame.midY)
        XCTAssertNil(SnapIslandLayout.hit(at: gap, layouts: layouts, panel: panel, margins: .zero))
        let margins = SnapMargins(outer: 8, inner: 24)
        let tiles = SnapIslandLayout.tiles(layouts: layouts, panel: panel, margins: margins)
        let firstGap = CGPoint(x: (tiles[0].frame.maxX + tiles[1].frame.minX) / 2, y: tiles[0].frame.midY)
        XCTAssertNil(SnapIslandLayout.hit(at: firstGap, layouts: layouts, panel: panel, margins: margins))
    }

    func testNoLayoutsMeansNoDropTargets() {
        let panel = CGRect(x: 0, y: 0, width: 560, height: 110)
        XCTAssertTrue(SnapIslandLayout.tiles(layouts: [], panel: panel, margins: .zero).isEmpty)
        XCTAssertNil(SnapIslandLayout.hit(at: CGPoint(x: 100, y: 50), layouts: [], panel: panel, margins: .zero))
    }
}
