//
//  SnapGridGeometryTests.swift
//  Light Stats Tests
//
//  Regression net for the layout geometry and the gap rule.
//
//  The gap rule is the part that is easy to get subtly wrong: two neighbouring tiles have to end up
//  exactly `inner` apart whether they are the second and third of a 3×1 row or the left half and
//  the top-right quarter of a stacked layout. The tests below pin the rule rather than the numbers,
//  and they also pin the invariant that the fixed actions and the normalized layout path agree —
//  they are two implementations of one idea, and nothing else checks that they stayed in step.
//

import XCTest
@testable import Light_Stats

final class SnapGridGeometryTests: XCTestCase {

    /// Accessibility-space visible frame of a laptop screen with a menu bar: 1512×982 display,
    /// 38pt menu bar.
    private let bounds = CGRect(x: 0, y: 38, width: 1512, height: 944)

    // MARK: - No margins

    func testZeroMarginsReproduceThePlainGrid() {
        let left = SnapGridGeometry.frame(for: .leftHalf, in: bounds, margins: .zero)
        XCTAssertEqual(left, CGRect(x: 0, y: 38, width: 756, height: 944))

        let bottomRight = SnapGridGeometry.frame(for: .bottomRightQuarter, in: bounds, margins: .zero)
        XCTAssertEqual(bottomRight, CGRect(x: 756, y: 510, width: 756, height: 472))
    }

    func testThirdOfTheGridIsAThirdOfTheWidth() {
        let middle = SnapNormalizedRect(columns: 3, rows: 1, column: 1, row: 0)
        let frame = SnapGridGeometry.frame(for: middle, in: bounds, margins: .zero)
        XCTAssertEqual(frame.minX, 504, accuracy: 0.0001)
        XCTAssertEqual(frame.width, 504, accuracy: 0.0001)
    }

    // MARK: - Margins

    func testOuterMarginInsetsEveryEdgeOfTheWholeScreenTile() {
        let margins = SnapMargins(outer: 12, inner: 0)
        let frame = SnapGridGeometry.frame(for: .full, in: bounds, margins: margins)
        XCTAssertEqual(frame, CGRect(x: 12, y: 50, width: 1488, height: 920))
    }

    /// The outer margin applies to the tile edge that meets the screen, and half the inner gap to
    /// the edge that meets another window. Left half + right half therefore differ by `inner`.
    func testInnerGapSplitsAcrossTheSharedEdge() {
        let margins = SnapMargins(outer: 10, inner: 20)
        let left = SnapGridGeometry.frame(for: .leftHalf, in: bounds, margins: margins)
        let right = SnapGridGeometry.frame(for: .rightHalf, in: bounds, margins: margins)

        XCTAssertEqual(left.minX, 10, accuracy: 0.0001)
        XCTAssertEqual(right.maxX, 1502, accuracy: 0.0001)
        XCTAssertEqual(right.minX - left.maxX, 20, accuracy: 0.0001)
    }

    func testVerticalStackSharesOneGapToo() {
        let margins = SnapMargins(outer: 0, inner: 16)
        let top = SnapGridGeometry.frame(for: .topHalf, in: bounds, margins: margins)
        let bottom = SnapGridGeometry.frame(for: .bottomHalf, in: bounds, margins: margins)
        XCTAssertEqual(bottom.minY - top.maxY, 16, accuracy: 0.0001)
        XCTAssertEqual(top.minY, 38, accuracy: 0.0001)
        XCTAssertEqual(bottom.maxY, 982, accuracy: 0.0001)
    }

    /// A stacked layout's interior edges are all interior — none of them may claim the outer margin.
    func testRightStackSharesGapsOnEveryInteriorEdge() {
        let margins = SnapMargins(outer: 8, inner: 12)
        let layout = SnapLayoutCatalog.rightStack
        let frames = SnapGridGeometry.frames(for: layout, in: bounds, margins: margins)
        XCTAssertEqual(frames.count, 3)

        let left = frames[0]
        let topRight = frames[1]
        let bottomRight = frames[2]

        XCTAssertEqual(topRight.minX - left.maxX, 12, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.minY - topRight.maxY, 12, accuracy: 0.0001)
        XCTAssertEqual(left.minX, 8, accuracy: 0.0001)
        XCTAssertEqual(topRight.maxX, 1504, accuracy: 0.0001)
    }

    func testMarginsLargerThanTheScreenDoNotInvertTheRect() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 80)
        let margins = SnapMargins(outer: 64, inner: 64)
        let frame = SnapGridGeometry.frame(for: .leftHalf, in: tiny, margins: margins)
        XCTAssertGreaterThanOrEqual(frame.width, 0)
        XCTAssertGreaterThanOrEqual(frame.height, 0)
    }

    func testClampedMarginsRejectAbsurdValues() {
        let margins = SnapMargins(outer: 5_000, inner: -10)
        XCTAssertEqual(margins.outer, SnapMargins.maximumGap)
        XCTAssertEqual(margins.inner, 0)
    }

    // MARK: - The two paths agree

    /// Fixed actions go through `WindowSnapGeometry`; layouts go through the normalized path. They
    /// have to produce the same rectangle, or a shortcut and the island would place a window in two
    /// slightly different places.
    func testActionRegionsMatchTheNormalizedPath() {
        let margins = SnapMargins(outer: 8, inner: 10)
        for action in WindowSnapAction.allCases {
            guard let normalized = WindowSnapGeometry.normalizedRect(for: action) else { continue }
            guard let fromAction = WindowSnapGeometry.regionFrame(for: action, bounds: bounds, margins: margins) else {
                XCTFail("\(action) has a normalized rect but no region frame")
                continue
            }
            let fromNormalized = SnapGridGeometry.frame(for: normalized, in: bounds, margins: margins)
            XCTAssertEqual(fromAction.minX, fromNormalized.minX, accuracy: 0.001, "\(action).x")
            XCTAssertEqual(fromAction.minY, fromNormalized.minY, accuracy: 0.001, "\(action).y")
            XCTAssertEqual(fromAction.width, fromNormalized.width, accuracy: 0.001, "\(action).width")
            XCTAssertEqual(fromAction.height, fromNormalized.height, accuracy: 0.001, "\(action).height")
        }
    }

    func testEveryActionWithANormalizedRectHasARegionFrame() {
        for action in WindowSnapAction.allCases {
            let hasNormalized = WindowSnapGeometry.normalizedRect(for: action) != nil
            let hasFrame = WindowSnapGeometry.regionFrame(for: action, bounds: bounds) != nil
            XCTAssertEqual(hasNormalized, hasFrame, "\(action)")
        }
    }

    /// The actions that are not regions must say so, because the display moves and center depend on
    /// the window rather than on the screen.
    func testNonRegionActionsHaveNoRect() {
        let nonRegions: [WindowSnapAction] = [.center, .restore, .minimize, .nextDisplay, .previousDisplay]
        for action in nonRegions {
            XCTAssertNil(WindowSnapGeometry.normalizedRect(for: action), "\(action)")
        }
    }
}
