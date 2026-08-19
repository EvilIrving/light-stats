//
//  FanAnimationLayerTests.swift
//  Light Stats Tests
//
//  Regression net for the status-bar fan's speed mapping and layer-copy lifecycle.
//

import AppKit
import QuartzCore
import XCTest
@testable import Light_Stats

@MainActor
final class FanAnimationLayerTests: XCTestCase {

    func testZeroOrUnknownRPMStopsAnimation() {
        XCTAssertEqual(FanAnimationLayer.visualSpeed(for: nil), 0)
        XCTAssertEqual(FanAnimationLayer.visualSpeed(for: 0), 0)
        XCTAssertEqual(FanAnimationLayer.visualSpeed(for: -1), 0)
    }

    func testRPMMapsLinearlyBelowCap() {
        XCTAssertEqual(FanAnimationLayer.visualSpeed(for: 2_500), 1.5, accuracy: 0.0001)
    }

    func testRPMCapsAtThreeRevolutionsPerSecond() {
        XCTAssertEqual(FanAnimationLayer.visualSpeed(for: 5_000), 3, accuracy: 0.0001)
        XCTAssertEqual(FanAnimationLayer.visualSpeed(for: 8_000), 3, accuracy: 0.0001)
    }

    func testPresentationLayerCopiesExistingTreeWithoutAddingModelLayers() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 24),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hostView = NSView(frame: window.contentView?.bounds ?? .zero)
        hostView.wantsLayer = true
        window.contentView = hostView

        let fanLayer = FanAnimationLayer()
        fanLayer.frame = NSRect(x: 0, y: 0, width: 22, height: 22)
        let hostLayer = try XCTUnwrap(hostView.layer)
        hostLayer.addSublayer(fanLayer)
        fanLayer.update(rpm: 2_500, visible: true, contentsScale: 2, tintColor: .labelColor)
        fanLayer.layoutIfNeeded()

        window.orderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let presentationLayer = try XCTUnwrap(fanLayer.presentation())
        XCTAssertEqual(fanLayer.sublayers?.count, 1)
        XCTAssertEqual(presentationLayer.sublayers?.count, 1)
    }
}
