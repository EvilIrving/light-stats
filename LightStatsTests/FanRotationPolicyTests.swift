//
//  FanRotationPolicyTests.swift
//  Light Stats Tests
//
//  Regression net for the rpm → visual speed mapping shared by the status bar
//  layer and the popover fan.
//

import XCTest
@testable import Light_Stats

final class FanRotationPolicyTests: XCTestCase {

    func testUnknownOrZeroRPMDoesNotSpin() {
        XCTAssertEqual(FanRotationPolicy.revolutionsPerSecond(rpm: nil), 0)
        XCTAssertEqual(FanRotationPolicy.revolutionsPerSecond(rpm: 0), 0)
        XCTAssertEqual(FanRotationPolicy.revolutionsPerSecond(rpm: -1), 0)
    }

    func testRPMMapsLinearlyBelowCap() {
        XCTAssertEqual(
            FanRotationPolicy.revolutionsPerSecond(rpm: 2_500),
            1.5,
            accuracy: 0.0001,
            "半速风扇应转半圈"
        )
    }

    func testRPMCapsAtThreeRevolutionsPerSecond() {
        XCTAssertEqual(FanRotationPolicy.revolutionsPerSecond(rpm: 5_000), 3, accuracy: 0.0001)
        XCTAssertEqual(FanRotationPolicy.revolutionsPerSecond(rpm: 8_000), 3, accuracy: 0.0001)
    }
}
