//
//  PowerServiceDiagnosticsTests.swift
//  LightStatsTests
//

import Foundation
import XCTest
@testable import Light_Stats

final class PowerServiceDiagnosticsTests: XCTestCase {
    func testHealthReasonDistinguishesMissingDesignCapacity() {
        let properties: [String: Any] = ["AppleRawMaxCapacity": NSNumber(value: 5_000)]
        XCTAssertEqual(PowerService.healthFailureReason(properties), "missingDesignCapacity")
    }

    func testHealthReasonDistinguishesInvalidDesignCapacityType() {
        let properties: [String: Any] = [
            "DesignCapacity": Data([0x01]),
            "AppleRawMaxCapacity": NSNumber(value: 5_000)
        ]
        XCTAssertEqual(PowerService.healthFailureReason(properties), "invalidDesignCapacityType")
    }

    func testHealthReasonDistinguishesMissingMaximumCapacity() {
        let properties: [String: Any] = ["DesignCapacity": NSNumber(value: 5_000)]
        XCTAssertEqual(PowerService.healthFailureReason(properties), "missingOrInvalidMaximumCapacity")
    }

    func testTemperatureReasonDistinguishesMissingTypeAndRange() {
        XCTAssertEqual(
            PowerService.batteryTemperatureReason(properties: [:], value: nil),
            "missingTemperature"
        )
        XCTAssertEqual(
            PowerService.batteryTemperatureReason(properties: ["Temperature": Data()], value: nil),
            "invalidTemperatureType"
        )
        XCTAssertEqual(
            PowerService.batteryTemperatureReason(
                properties: ["Temperature": NSNumber(value: 9_000)],
                value: nil
            ),
            "temperatureOutOfRange"
        )
    }

    func testTemperatureSuccessHasExplicitReason() {
        XCTAssertEqual(
            PowerService.batteryTemperatureReason(
                properties: ["Temperature": NSNumber(value: 3_000)],
                value: 30
            ),
            "valueRead"
        )
    }
}
