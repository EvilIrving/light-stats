//
//  FanAnimationLayerTests.swift
//  Light Stats Tests
//
//  Regression net for the status-bar fan's speed mapping and layer-copy lifecycle.
//

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
}
