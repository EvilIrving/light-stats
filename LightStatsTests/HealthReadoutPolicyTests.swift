//
//  HealthReadoutPolicyTests.swift
//  Light Stats Tests
//
//  健康度两个口径切换时的滚动方向：方向必须指向新值的相对大小——
//  它本身就是「哪个口径更高」的信息，方向反了等于读数在说谎。
//

import XCTest
@testable import Light_Stats

final class HealthReadoutPolicyTests: XCTestCase {

    func testSwitchingToLargerSystemValueRollsUp() {
        XCTAssertFalse(
            HealthReadoutPolicy.countsDown(showsSystem: true, healthPercent: 80, systemPercent: 84),
            "本机 80 → 系统 84，切到更大的值应向上滚"
        )
    }

    func testSwitchingBackToSmallerDeviceValueRollsDown() {
        XCTAssertTrue(
            HealthReadoutPolicy.countsDown(showsSystem: false, healthPercent: 80, systemPercent: 84),
            "系统 84 → 本机 80，切回更小的值应向下滚"
        )
    }

    func testDirectionFollowsValuesNotSide() {
        // 某台机器系统值反而更低时，方向跟着数值走，不跟「系统值」这个身份走。
        XCTAssertTrue(
            HealthReadoutPolicy.countsDown(showsSystem: true, healthPercent: 90, systemPercent: 85)
        )
        XCTAssertFalse(
            HealthReadoutPolicy.countsDown(showsSystem: false, healthPercent: 90, systemPercent: 85)
        )
    }

    func testEqualValuesNeverRollDown() {
        XCTAssertFalse(
            HealthReadoutPolicy.countsDown(showsSystem: true, healthPercent: 84, systemPercent: 84)
        )
    }

    func testMissingValueHasNoDirection() {
        XCTAssertFalse(
            HealthReadoutPolicy.countsDown(showsSystem: true, healthPercent: 80, systemPercent: nil)
        )
        XCTAssertFalse(
            HealthReadoutPolicy.countsDown(showsSystem: false, healthPercent: nil, systemPercent: 84)
        )
    }
}
