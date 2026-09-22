//
//  FanHardwarePolicyTests.swift
//  Light Stats Tests
//
//  Fan surfaces hide only when SMC reports no fan keys. Read failures stay visible.
//

import XCTest
@testable import Light_Stats

final class FanHardwarePolicyTests: XCTestCase {

    func testNoFanKeysHidesSurfaces() {
        XCTAssertFalse(
            FanHardwarePolicy.shouldShowSurfaces(reasonCode: SMCInfo.FanReason.noFanKeys),
            "无风扇机型不应再露出风扇状态栏 / Overview / 设置开关"
        )
    }

    func testSuccessfulReadsKeepSurfaces() {
        XCTAssertTrue(FanHardwarePolicy.shouldShowSurfaces(reasonCode: SMCInfo.FanReason.valueRead))
        XCTAssertTrue(FanHardwarePolicy.shouldShowSurfaces(reasonCode: SMCInfo.FanReason.fallbackIndexRead))
        XCTAssertTrue(
            FanHardwarePolicy.shouldShowSurfaces(reasonCode: SMCInfo.FanReason.valueReadAfterReconnect)
        )
    }

    func testReadFailuresNeverHideSurfaces() {
        XCTAssertTrue(
            FanHardwarePolicy.shouldShowSurfaces(reasonCode: SMCInfo.FanReason.fanKeysUnreadable),
            "键在但读不出是回归信号，不能当成无风扇"
        )
        XCTAssertTrue(
            FanHardwarePolicy.shouldShowSurfaces(reasonCode: SMCInfo.FanReason.connectionUnavailable)
        )
        XCTAssertTrue(
            FanHardwarePolicy.shouldShowSurfaces(reasonCode: SMCInfo.FanReason.reconnectFailed)
        )
    }

    func testUnresolvedProbeKeepsSurfaces() {
        XCTAssertTrue(
            FanHardwarePolicy.shouldShowSurfaces(reasonCode: "notCollected"),
            "尚未探测完成时不能抢先隐藏"
        )
        XCTAssertTrue(FanHardwarePolicy.shouldShowSurfaces(reasonCode: "unknown"))
    }
}
