//
//  WindowSnapGeometryTests.swift
//  Light Stats Tests
//
//  Regression net for the snap engine's placement math and for the Accessibility ↔ Cocoa flip.
//
//  The flip reference is the bug this file exists for: it has to be the primary display's
//  `frame.maxY`, because Accessibility `y = 0` is that display's top edge. Using the topmost
//  display instead shifted every frame by the height of whatever sat above the primary one, which
//  is how window snapping broke on external displays while the built-in screen kept working.
//

import XCTest
@testable import Light_Stats

final class WindowSnapGeometryTests: XCTestCase {

    /// Accessibility-space visible frame of a laptop screen with a menu bar: 1512×982 display,
    /// 38pt menu bar, so the visible area starts 38pt below the top edge.
    private let visibleFrame = CGRect(x: 0, y: 38, width: 1512, height: 944)

    private func target(_ action: WindowSnapAction, size: CGSize = CGSize(width: 800, height: 600)) -> CGRect {
        WindowSnapGeometry.targetFrame(for: action, visibleFrame: visibleFrame, currentSize: size)
    }

    func testHalvesSplitTheVisibleFrame() {
        XCTAssertEqual(target(.leftHalf), CGRect(x: 0, y: 38, width: 756, height: 944))
        XCTAssertEqual(target(.rightHalf), CGRect(x: 756, y: 38, width: 756, height: 944))
        XCTAssertEqual(target(.topHalf), CGRect(x: 0, y: 38, width: 1512, height: 472))
        XCTAssertEqual(target(.bottomHalf), CGRect(x: 0, y: 510, width: 1512, height: 472))
    }

    func testQuartersMeetInTheMiddle() {
        let topLeft = target(.topLeft)
        let topRight = target(.topRight)
        let bottomLeft = target(.bottomLeft)
        let bottomRight = target(.bottomRight)

        XCTAssertEqual(topLeft, CGRect(x: 0, y: 38, width: 756, height: 472))
        XCTAssertEqual(bottomRight, CGRect(x: 756, y: 510, width: 756, height: 472))
        XCTAssertEqual(topLeft.maxX, topRight.minX)
        XCTAssertEqual(topLeft.maxY, bottomLeft.minY)
        XCTAssertEqual(bottomRight.minX, topRight.minX)
        XCTAssertEqual(bottomRight.minY, bottomLeft.minY)
    }

    func testThirdsCoverTheWidthWithoutGaps() {
        let third = visibleFrame.width / 3
        XCTAssertEqual(target(.leftThird), CGRect(x: 0, y: 38, width: third, height: 944))
        XCTAssertEqual(target(.centerThird), CGRect(x: third, y: 38, width: third, height: 944))
        XCTAssertEqual(target(.rightThird), CGRect(x: third * 2, y: 38, width: third, height: 944))
        XCTAssertEqual(target(.leftTwoThirds), CGRect(x: 0, y: 38, width: third * 2, height: 944))
        XCTAssertEqual(target(.rightTwoThirds), CGRect(x: third, y: 38, width: third * 2, height: 944))
    }

    func testMaximizeFillsTheVisibleFrame() {
        XCTAssertEqual(target(.maximize), visibleFrame)
    }

    func testCenterKeepsTheWindowSizeAndCentersIt() {
        let centered = target(.center, size: CGSize(width: 800, height: 600))
        XCTAssertEqual(centered.size, CGSize(width: 800, height: 600))
        XCTAssertEqual(centered.midX, visibleFrame.midX)
        XCTAssertEqual(centered.midY, visibleFrame.midY)
    }

    func testCenterShrinksAWindowThatCannotFit() {
        let centered = target(.center, size: CGSize(width: 2000, height: 1200))
        XCTAssertEqual(centered.size, visibleFrame.size)
        XCTAssertEqual(centered.origin, visibleFrame.origin)
    }

    // MARK: - Accessibility ↔ Cocoa flip

    /// The flip is its own inverse, so the two conversion directions cannot drift apart.
    func testFlipIsItsOwnInverse() {
        let rect = CGRect(x: -1200, y: 38, width: 756, height: 944)
        let flipped = WindowSnapGeometry.flip(rect, aboutMaxY: 982)
        XCTAssertEqual(flipped, CGRect(x: -1200, y: 0, width: 756, height: 944))
        XCTAssertEqual(WindowSnapGeometry.flip(flipped, aboutMaxY: 982), rect)
    }

    /// A full-height frame on the primary display maps onto itself: its top edge is the reference,
    /// which is the property that pins the reference to the primary display.
    func testPrimaryDisplayFrameMapsOntoItself() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(WindowSnapGeometry.flip(primary, aboutMaxY: primary.maxY), primary)
    }

    /// A display arranged above the primary lives at negative Accessibility y, because Accessibility
    /// y grows downward from the primary's top edge.
    func testDisplayAboveThePrimaryUsesNegativeAccessibilityY() {
        // A 2560×1440 display sitting directly above a 1512×982 primary.
        let externalCocoa = CGRect(x: 0, y: 982, width: 2560, height: 1440)
        let primaryMaxY: CGFloat = 982

        let externalAX = WindowSnapGeometry.flip(externalCocoa, aboutMaxY: primaryMaxY)
        XCTAssertEqual(externalAX.minY, -1440)
        XCTAssertEqual(externalAX.maxY, 0)

        // Flipping with the display stack's highest maxY instead — the defect this guards against —
        // shifts the frame by exactly the external display's height, which is why windows landed a
        // whole screen away once an external display was arranged above the built-in one.
        let wrongReference = externalCocoa.maxY
        let shifted = WindowSnapGeometry.flip(externalCocoa, aboutMaxY: wrongReference)
        XCTAssertEqual(shifted.minY - externalAX.minY, wrongReference - primaryMaxY)
        XCTAssertEqual(shifted.minY - externalAX.minY, externalCocoa.height)
    }

    // MARK: - Moving between displays

    func testTransferredFrameKeepsRelativeSizeAndPosition() {
        let source = CGRect(x: 0, y: 38, width: 1512, height: 944)
        let target = CGRect(x: 1512, y: 0, width: 2560, height: 1400)
        let leftHalf = CGRect(x: 0, y: 38, width: 756, height: 944)

        let moved = WindowSnapGeometry.transferredFrame(leftHalf, from: source, to: target)

        XCTAssertEqual(moved.minX, target.minX)
        XCTAssertEqual(moved.width, target.width / 2, accuracy: 0.001)
        XCTAssertEqual(moved.height, target.height, accuracy: 0.001)
    }

    /// A window whose proportional placement would push it off the target display gets pulled back
    /// inside, keeping its relative size, instead of being cropped by `intersection`.
    func testTransferredFrameStaysInsideTheTargetDisplay() {
        let source = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let target = CGRect(x: 1512, y: 0, width: 1280, height: 800)
        let nearRightEdge = CGRect(x: 712, y: 0, width: 800, height: 982)

        let moved = WindowSnapGeometry.transferredFrame(nearRightEdge, from: source, to: target)

        XCTAssertEqual(moved.width, 800.0 / 1512.0 * 1280.0, accuracy: 0.001)
        XCTAssertEqual(moved.height, 800, accuracy: 0.001)
        XCTAssertEqual(moved.maxX, target.maxX, accuracy: 0.001)
        XCTAssertEqual(moved.maxY, target.maxY, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(moved.minX, target.minX)
        XCTAssertGreaterThanOrEqual(moved.minY, target.minY)
    }

    func testDegenerateSourceFallsBackToTheTarget() {
        let target = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = CGRect(x: 10, y: 10, width: 100, height: 100)
        let moved = WindowSnapGeometry.transferredFrame(frame, from: .zero, to: target)
        XCTAssertEqual(moved, target)
    }

    // MARK: - Titlebar band

    /// The band comes from where the system put each app's traffic lights, measured on this Mac:
    /// cmux 32pt, VS Code 34pt, ChatGPT 46pt, Fork 52pt. A 44pt constant is 10–12pt too tall for the
    /// first two and 8pt too short for the last, which is why this is derived and not fixed.
    func testTitlebarHeightFollowsTheTrafficLights() {
        let window = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let cases: [(name: String, closeButtonY: CGFloat, expected: CGFloat)] = [
            ("cmux", 8, 32),
            ("VS Code", 9, 34),
            ("ChatGPT", 15, 46),
            ("Fork", 18, 52)
        ]
        for entry in cases {
            let trafficLights = CGRect(x: 10, y: entry.closeButtonY, width: 54, height: 16)
            XCTAssertEqual(
                WindowSnapGeometry.titlebarHeight(windowFrame: window, trafficLights: trafficLights),
                entry.expected,
                entry.name
            )
        }
    }

    func testTitlebarHeightFallsBackWithoutTrafficLights() {
        let window = CGRect(x: 0, y: 0, width: 1280, height: 800)
        XCTAssertEqual(
            WindowSnapGeometry.titlebarHeight(windowFrame: window, trafficLights: nil),
            WindowSnapGeometry.fallbackTitlebarHeight
        )
        XCTAssertEqual(
            WindowSnapGeometry.titlebarHeight(windowFrame: window, trafficLights: .zero),
            WindowSnapGeometry.fallbackTitlebarHeight
        )
    }

    func testTitlebarHeightIgnoresAbsurdTrafficLightPlacement() {
        let window = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let above = CGRect(x: 10, y: -40, width: 54, height: 16)
        let farBelow = CGRect(x: 10, y: 400, width: 54, height: 16)
        XCTAssertEqual(
            WindowSnapGeometry.titlebarHeight(windowFrame: window, trafficLights: above),
            WindowSnapGeometry.fallbackTitlebarHeight
        )
        XCTAssertEqual(
            WindowSnapGeometry.titlebarHeight(windowFrame: window, trafficLights: farBelow),
            WindowSnapGeometry.fallbackTitlebarHeight
        )
    }

    func testTitlebarBandStopsAtTheMeasuredHeight() {
        let window = CGRect(x: 100, y: 50, width: 1280, height: 800)
        // 9pt inset → 34pt band, i.e. y = 50…84.
        let trafficLights = CGRect(x: 110, y: 59, width: 54, height: 16)
        XCTAssertTrue(WindowSnapGeometry.isInTitlebar(CGPoint(x: 700, y: 60), windowFrame: window, trafficLights: trafficLights))
        XCTAssertTrue(WindowSnapGeometry.isInTitlebar(CGPoint(x: 700, y: 84), windowFrame: window, trafficLights: trafficLights))
        XCTAssertFalse(WindowSnapGeometry.isInTitlebar(CGPoint(x: 700, y: 90), windowFrame: window, trafficLights: trafficLights))
        XCTAssertFalse(WindowSnapGeometry.isInTitlebar(CGPoint(x: 700, y: 40), windowFrame: window, trafficLights: trafficLights))
    }

    // MARK: - Native command mapping

    /// Everything macOS tiles natively has to be routed to the system implementation, and only what
    /// it has no command for may fall through to the engine's own placement.
    func testNativeMappingCoversTheSystemCommands() {
        let nativelyTiled: [WindowSnapAction: NativeTilingCommand] = [
            .leftHalf: .left,
            .rightHalf: .right,
            .topHalf: .top,
            .bottomHalf: .bottom,
            .topLeft: .topLeft,
            .topRight: .topRight,
            .bottomLeft: .bottomLeft,
            .bottomRight: .bottomRight,
            .maximize: .fill,
            .center: .center,
            .restore: .untile
        ]
        for (action, command) in nativelyTiled {
            XCTAssertEqual(NativeTilingCommand.matching(action), command, "\(action)")
        }

        let engineOnly: [WindowSnapAction] = [
            .leftThird, .leftTwoThirds, .centerThird, .rightTwoThirds, .rightThird,
            .nextDisplay, .previousDisplay, .minimize
        ]
        for action in engineOnly {
            XCTAssertNil(NativeTilingCommand.matching(action), "\(action)")
        }
    }

    func testNativeIdentifiersAreUniqueAndWellFormed() {
        let identifiers = NativeTilingCommand.allCases.map(\.accessibilityIdentifier)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        for identifier in identifiers {
            XCTAssertTrue(identifier.hasPrefix("_zoom"), identifier)
            XCTAssertTrue(identifier.hasSuffix(":"), identifier)
        }
    }
}
