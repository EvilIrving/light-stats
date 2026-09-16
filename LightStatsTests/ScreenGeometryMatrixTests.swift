//
//  ScreenGeometryMatrixTests.swift
//  Light Stats Tests
//
//  The display-arrangement net for the Accessibility ↔ Cocoa conversion and the placement math.
//
//  The development machine is one arrangement, and the reports come from the arrangements it is not:
//  a display above the primary, one at negative x, an ultrawide beside a 1080p, a Dock that eats into
//  the visible frame from the side. Nothing here touches AppKit — the snapshot is built from injected
//  Cocoa rectangles and `resolvedFrame` is a pure function over a screen value — so an arrangement
//  no test machine has can still be asserted end to end.
//

import XCTest
@testable import Light_Stats

final class ScreenGeometryMatrixTests: XCTestCase {

    /// 4K primary (menu bar above, Dock on the left), 5K above it, 1080p to the left, 32:9 ultrawide
    /// to the right. The primary is listed first because that is what `NSScreen.screens` does and what
    /// the reference height is read from.
    private let arrangement: [(frame: CGRect, visibleFrame: CGRect)] = [
        (CGRect(x: 0, y: 0, width: 3840, height: 2160), CGRect(x: 78, y: 0, width: 3762, height: 2105)),
        (CGRect(x: 0, y: 2160, width: 5120, height: 2880), CGRect(x: 0, y: 2160, width: 5120, height: 2880)),
        (CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: -1920, y: 0, width: 1920, height: 1080)),
        (CGRect(x: 3840, y: 0, width: 5120, height: 1440), CGRect(x: 3840, y: 0, width: 5120, height: 1440))
    ]

    /// Every action that produces a rectangle. Display moves and window control are not geometry and
    /// are covered elsewhere.
    private let rectangleActions: [WindowSnapAction] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .topLeft, .topRight, .bottomLeft, .bottomRight,
        .leftThird, .leftTwoThirds, .centerThird, .rightTwoThirds, .rightThird,
        .maximize, .center
    ]

    private func matrix() -> ScreenGeometryProvider.Snapshot {
        ScreenGeometryProvider.snapshot(cocoaFrames: arrangement)
    }

    private func screen(width: CGFloat, height: CGFloat) throws -> SnapScreenGeometry {
        try XCTUnwrap(
            matrix().screens.first { $0.frame.width == width && $0.frame.height == height },
            "no display of \(width)×\(height) in the arrangement"
        )
    }

    private func resolved(
        _ action: WindowSnapAction,
        on screen: SnapScreenGeometry,
        size: CGSize = CGSize(width: 800, height: 600)
    ) throws -> CGRect {
        try XCTUnwrap(
            WindowPlacementEngine.resolvedFrame(
                for: .action(action), screen: screen, margins: .zero, currentSize: size
            ),
            "\(action) resolved no frame on display \(screen.index)"
        )
    }

    // MARK: - Reference height

    /// The reference is the primary display's `frame.maxY`, and the primary is the display the system
    /// lists first — not whichever display happens to sit at `(0, 0)`.
    func testReferenceFollowsTheFirstDisplayWhateverItsOrigin() {
        let primary = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let secondary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(ScreenGeometryProvider.referenceMaxY(cocoaFrames: [primary, secondary]), 1440)
        XCTAssertEqual(ScreenGeometryProvider.referenceMaxY(cocoaFrames: [primary]), 1440)
    }

    /// No displays used to be answered by an origin search that fell back to `0` — the value that
    /// mirrors every rectangle in the app. It still answers `0`, but from one rule instead of two.
    func testReferenceWithoutDisplaysIsZero() {
        XCTAssertEqual(ScreenGeometryProvider.referenceMaxY(cocoaFrames: []), 0)
        XCTAssertEqual(matrix().referenceMaxY, 2160)
    }

    /// The primary display is the one that lands on the Accessibility origin; every other display is
    /// measured from it. A reference taken from the topmost display instead would push the primary
    /// 2880pt down the axis — every window on it would be placed a whole screen away.
    func testThePrimaryDisplaySitsAtAccessibilityOrigin() throws {
        let primary = try screen(width: 3840, height: 2160)
        XCTAssertEqual(primary.frame, CGRect(x: 0, y: 0, width: 3840, height: 2160))
        XCTAssertTrue(primary.frame.contains(CGPoint.zero))

        for other in matrix().screens where other.index != primary.index {
            XCTAssertFalse(other.frame.contains(CGPoint.zero), "display \(other.index) also claims the origin")
        }

        let primaryCocoa = try XCTUnwrap(arrangement.first?.frame)
        XCTAssertEqual(WindowSnapGeometry.flip(primaryCocoa, aboutMaxY: 5040).minY, 2880)
    }

    // MARK: - Ordering and the flip

    /// Ordered top-to-bottom, then left-to-right, in Accessibility space — so "next display" means
    /// the same thing on a vertical stack as on a horizontal row.
    func testAnArrangementOrdersTopToBottomThenLeftToRight() {
        let screens = matrix().screens
        XCTAssertEqual(screens.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(
            screens.map(\.frame),
            [
                CGRect(x: 0, y: -2880, width: 5120, height: 2880),   // the 5K above the primary
                CGRect(x: 0, y: 0, width: 3840, height: 2160),       // the primary
                CGRect(x: 3840, y: 720, width: 5120, height: 1440),  // the ultrawide on the right
                CGRect(x: -1920, y: 1080, width: 1920, height: 1080) // the 1080p on the left
            ]
        )
    }

    /// A visible frame that excludes a menu bar and a side Dock has to survive the flip intact — it is
    /// the only area the engine is allowed to place into.
    func testVisibleFrameFlipsWithItsMenuBarAndDockInsets() throws {
        let primary = try screen(width: 3840, height: 2160)
        XCTAssertEqual(primary.visibleFrame, CGRect(x: 78, y: 55, width: 3762, height: 2105))

        for geometry in matrix().screens {
            XCTAssertTrue(
                geometry.frame.insetBy(dx: -0.001, dy: -0.001).contains(geometry.visibleFrame),
                "display \(geometry.index): visible frame escapes the display"
            )
        }
    }

    // MARK: - Placement across the arrangement

    /// Every action, on every display, lands inside that display's visible area. This is the property
    /// a wrong reference height or a bad flip breaks first.
    func testEveryActionLandsInsideTheVisibleFrameOnEveryDisplay() throws {
        for geometry in matrix().screens {
            let bounds = geometry.visibleFrame.insetBy(dx: -0.001, dy: -0.001)
            for action in rectangleActions {
                let frame = try resolved(action, on: geometry)
                XCTAssertTrue(bounds.contains(frame), "\(action) on display \(geometry.index): \(frame)")
            }
        }
    }

    /// Halves and thirds divide the **visible** frame, not the display: with the Dock on the left the
    /// left half starts after the Dock, and the menu bar is never covered.
    func testHalvesAndThirdsDivideTheVisibleFrameNotTheDisplay() throws {
        let primary = try screen(width: 3840, height: 2160)
        let visible = primary.visibleFrame

        let left = try resolved(.leftHalf, on: primary)
        let right = try resolved(.rightHalf, on: primary)
        XCTAssertEqual(left.minX, visible.minX)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(right.maxX, visible.maxX)
        XCTAssertNotEqual(left.minX, primary.frame.minX)
        XCTAssertEqual(left.minY, visible.minY)
        XCTAssertEqual(left.height, visible.height)

        let third = visible.width / 3
        let leftThird = try resolved(.leftThird, on: primary)
        let leftTwoThirds = try resolved(.leftTwoThirds, on: primary)
        let centerThird = try resolved(.centerThird, on: primary)
        let rightThird = try resolved(.rightThird, on: primary)
        XCTAssertEqual(leftThird.width, third, accuracy: 0.001)
        XCTAssertEqual(leftTwoThirds.width, third * 2, accuracy: 0.001)
        XCTAssertEqual(centerThird.minX, visible.minX + third, accuracy: 0.001)
        XCTAssertEqual(rightThird.maxX, visible.maxX, accuracy: 0.001)
    }

    /// The same rules hold on an aspect ratio the primary does not have: 32:9, where a quarter is
    /// wider than it is tall, and on a display with no menu bar and no Dock.
    func testHalvesAndQuartersHoldOnAnUltrawideAndOnAFullDisplay() throws {
        let ultrawide = try screen(width: 5120, height: 1440)
        let visible = ultrawide.visibleFrame

        let topLeft = try resolved(.topLeft, on: ultrawide)
        let bottomRight = try resolved(.bottomRight, on: ultrawide)
        XCTAssertEqual(topLeft, CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height / 2))
        XCTAssertEqual(bottomRight.maxX, visible.maxX)
        XCTAssertEqual(bottomRight.maxY, visible.maxY)
        let maximized = try resolved(.maximize, on: ultrawide)
        XCTAssertEqual(maximized, visible)

        let full = try screen(width: 5120, height: 2880)
        let fullMaximize = try resolved(.maximize, on: full)
        let fullBottomHalf = try resolved(.bottomHalf, on: full)
        XCTAssertEqual(fullMaximize, full.visibleFrame)
        XCTAssertEqual(fullBottomHalf.minY, full.visibleFrame.midY)
    }

    /// Centring keeps the window's size and puts it in the middle of the visible area, even when the
    /// Dock has moved that middle.
    func testCenteringUsesTheVisibleMiddle() throws {
        let primary = try screen(width: 3840, height: 2160)
        let centered = try resolved(.center, on: primary)
        XCTAssertEqual(centered.midX, primary.visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(centered.midY, primary.visibleFrame.midY, accuracy: 0.001)
        XCTAssertEqual(centered.size, CGSize(width: 800, height: 600))
    }

    /// Moving a window between two aspect ratios that share no dimension: the relative placement is
    /// preserved and the result is pulled inside the target rather than cropped.
    func testTransferBetweenDisplaysWithDifferentAspectRatios() throws {
        let tall = try screen(width: 5120, height: 2880)
        let ultrawide = try screen(width: 5120, height: 1440)

        let bottomHalf = try resolved(.bottomHalf, on: tall)
        let moved = WindowSnapGeometry.transferredFrame(
            bottomHalf, from: tall.visibleFrame, to: ultrawide.visibleFrame
        )

        XCTAssertEqual(moved.width, ultrawide.visibleFrame.width, accuracy: 0.001)
        XCTAssertEqual(moved.height, ultrawide.visibleFrame.height / 2, accuracy: 0.001)
        XCTAssertEqual(moved.minY, ultrawide.visibleFrame.midY, accuracy: 0.001)
        XCTAssertEqual(moved.maxX, ultrawide.visibleFrame.maxX, accuracy: 0.001)
    }

    /// The top boundary a drag is measured against is the visible area's — the island has to arm at
    /// the menu bar line, not inside the menu bar — while the sides stay physical so the pointer may
    /// enter the Dock.
    func testDragBoundariesUseTheVisibleTopAndThePhysicalSides() throws {
        let primary = try screen(width: 3840, height: 2160)
        let boundaries = primary.dragBoundaries
        XCTAssertEqual(boundaries.left, primary.frame.minX)
        XCTAssertEqual(boundaries.right, primary.frame.maxX)
        XCTAssertEqual(boundaries.bottom, primary.frame.maxY)
        XCTAssertEqual(boundaries.top, primary.visibleFrame.minY)
        XCTAssertNotEqual(boundaries.top, primary.frame.minY)
    }
}
