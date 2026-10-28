//
//  UpdateWindowGeometryTests.swift
//  Light Stats Tests
//
//  Pins the rule the update window's flake came from: the window is created at
//  the size it keeps. A maximum frame smaller than the created frame makes
//  AppKit resize a window nobody asked to resize, which is what the 2 pt jump
//  on a short CI display measured.
//

import XCTest
@testable import Light_Stats

final class UpdateWindowGeometryTests: XCTestCase {

    private let chrome: CGFloat = 28

    /// A tall screen keeps the preferred height, exactly as before this change.
    func testTallScreenKeepsThePreferredContentHeight() {
        let height = UpdateWindowGeometry.contentHeight(visibleHeight: 900, chromeHeight: chrome)
        XCTAssertEqual(height, UpdateWindowGeometry.preferredContentHeight)
    }

    /// A short screen shrinks the content so the *frame* fits the 85% margin,
    /// rather than letting the frame exceed it and be clamped afterwards.
    func testShortScreenSizesTheContentAroundTheTitleBar() {
        let height = UpdateWindowGeometry.contentHeight(visibleHeight: 570, chromeHeight: chrome)
        XCTAssertEqual(height, 570 * 0.85 - chrome, accuracy: 0.001)
        let frame = UpdateWindowGeometry.frameHeight(visibleHeight: 570, chromeHeight: chrome)
        XCTAssertEqual(frame, 570 * 0.85, accuracy: 0.001, "the frame, not the content, is what must fit")
    }

    /// The maximum must never be smaller than the created frame; otherwise
    /// assigning it resizes the window.
    func testMaximumFrameIsNeverSmallerThanTheCreatedFrame() {
        for visibleHeight in stride(from: 200.0, through: 1400.0, by: 7.0) {
            let frame = UpdateWindowGeometry.frameHeight(visibleHeight: visibleHeight, chromeHeight: chrome)
            let maximum = UpdateWindowGeometry.maximumFrameHeight(
                visibleHeight: visibleHeight,
                chromeHeight: chrome
            )
            XCTAssertGreaterThanOrEqual(
                maximum,
                frame,
                "a maximum below the created frame at visibleHeight \(visibleHeight) clamps the window"
            )
        }
    }

    /// A screen too short for the minimum still yields a usable window instead of
    /// a sliver or a negative height.
    func testAbsurdlyShortScreenKeepsTheMinimumHeight() {
        let height = UpdateWindowGeometry.contentHeight(visibleHeight: 120, chromeHeight: chrome)
        XCTAssertEqual(height, UpdateWindowGeometry.minimumContentHeight)
        XCTAssertGreaterThan(
            UpdateWindowGeometry.frameHeight(visibleHeight: 120, chromeHeight: chrome),
            0
        )
    }

    /// Nothing in the arithmetic may produce a negative height, which `NSWindow`
    /// would reject.
    func testHeightIsNeverNegative() {
        for visibleHeight in stride(from: 0.0, through: 200.0, by: 3.0) {
            XCTAssertGreaterThan(
                UpdateWindowGeometry.frameHeight(visibleHeight: visibleHeight, chromeHeight: chrome),
                0
            )
        }
    }
}
