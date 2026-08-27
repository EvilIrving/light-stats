//
//  FindMouseTriggerTests.swift
//  LightStatsTests
//
//  Drives the pure double-tap detector: alternation, window, cooldown, reset.
//

import XCTest
@testable import Light_Stats

final class FindMouseTriggerTests: XCTestCase {

    private var detector = FindMouseTriggerDetector()

    override func setUp() {
        super.setUp()
        detector = FindMouseTriggerDetector()
    }

    // MARK: - 基本触发

    func testSinglePressDoesNotTrigger() {
        XCTAssertFalse(detector.registerPress(at: 1.0))
    }

    func testDoublePressWithinWindowTriggers() {
        XCTAssertFalse(detector.registerPress(at: 1.0))
        detector.registerRelease(at: 1.1)
        XCTAssertTrue(detector.registerPress(at: 1.3))
    }

    func testSlowDoublePressDoesNotTrigger() {
        XCTAssertFalse(detector.registerPress(at: 1.0))
        detector.registerRelease(at: 1.1)
        XCTAssertFalse(detector.registerPress(at: 1.7))
    }

    // MARK: - 边界与防误触

    func testPressWithoutReleaseDoesNotTrigger() {
        XCTAssertFalse(detector.registerPress(at: 1.0))
        // 卡键：无中间抬起的再次按下不算双击。
        XCTAssertFalse(detector.registerPress(at: 1.2))
    }

    func testTriplePressDoesNotRetriggerWithinCooldown() {
        XCTAssertFalse(detector.registerPress(at: 1.0))
        detector.registerRelease(at: 1.1)
        XCTAssertTrue(detector.registerPress(at: 1.3))
        detector.registerRelease(at: 1.4)
        // Triple-tap still inside the 1.2s cooldown.
        XCTAssertFalse(detector.registerPress(at: 1.6))
        detector.registerRelease(at: 1.7)
        // New pair whose second press is still before 1.3 + 1.2 = 2.5.
        XCTAssertFalse(detector.registerPress(at: 2.0))
        detector.registerRelease(at: 2.1)
        XCTAssertFalse(detector.registerPress(at: 2.3))
        detector.registerRelease(at: 2.4)
        // Cooldown elapsed: 2.6 - 1.3 = 1.3 >= 1.2, and 2.6 is within 0.5s of 2.3.
        XCTAssertTrue(detector.registerPress(at: 2.6))
    }

    func testExactlyAtWindowBoundaryTriggers() {
        XCTAssertFalse(detector.registerPress(at: 1.0))
        detector.registerRelease(at: 1.1)
        // 间隔恰好等于 0.5s 窗口：闭区间，应触发。
        XCTAssertTrue(detector.registerPress(at: 1.5))
    }

    func testJustBeyondWindowDoesNotTrigger() {
        XCTAssertFalse(detector.registerPress(at: 1.0))
        detector.registerRelease(at: 1.1)
        XCTAssertFalse(detector.registerPress(at: 1.51))
    }

    func testReleaseAtSameInstantAsPressStillAlternates() {
        XCTAssertFalse(detector.registerPress(at: 1.0))
        detector.registerRelease(at: 1.0)
        // release == press 时刻：严格大于才算交替，卡键场景不触发。
        XCTAssertFalse(detector.registerPress(at: 1.2))
    }

    // MARK: - 重置

    func testResetClearsPendingState() {
        XCTAssertFalse(detector.registerPress(at: 1.0))
        detector.reset()
        detector.registerRelease(at: 1.05)
        // 重置后窗口从零开始，1.3s 的第二次按下是“新的第一次”。
        XCTAssertFalse(detector.registerPress(at: 1.3))
    }

    // MARK: - 触发键映射

    func testTriggerKeyKeyCodesMatchHIDUsage() {
        // kVK_Control / kVK_Option / kVK_Command / kVK_Shift 的经典键码。
        XCTAssertEqual(FindMouseTriggerKey.leftControl.keyCode, 59)
        XCTAssertEqual(FindMouseTriggerKey.leftOption.keyCode, 58)
        XCTAssertEqual(FindMouseTriggerKey.leftCommand.keyCode, 55)
        XCTAssertEqual(FindMouseTriggerKey.leftShift.keyCode, 56)
    }
}
