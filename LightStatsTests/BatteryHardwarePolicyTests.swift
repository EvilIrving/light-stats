//
//  BatteryHardwarePolicyTests.swift
//  Light Stats Tests
//
//  Battery surfaces hide only when the machine has no internal battery.
//

import XCTest
@testable import Light_Stats

final class BatteryHardwarePolicyTests: XCTestCase {

    func testNoInternalBatteryHidesSurfaces() {
        XCTAssertFalse(
            BatteryHardwarePolicy.shouldShowSurfaces(hasInternalBattery: false),
            "台式 / 无电池机型不应再露出电池状态栏 / Overview / 设置开关"
        )
    }

    func testInternalBatteryKeepsSurfaces() {
        XCTAssertTrue(
            BatteryHardwarePolicy.shouldShowSurfaces(hasInternalBattery: true),
            "有内置电池时三处表面保持可见"
        )
    }
}
