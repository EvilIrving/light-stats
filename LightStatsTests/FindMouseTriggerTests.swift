//
//  FindMouseTriggerTests.swift
//  LightStatsTests
//
//  Drives the shared double/triple-tap detector.
//

import XCTest
@testable import Light_Stats

final class FindMouseTriggerTests: XCTestCase {

    private var detector = FindMouseTriggerDetector()

    override func setUp() {
        super.setUp()
        detector = FindMouseTriggerDetector()
    }

    // MARK: - Double tap

    func testSinglePressDoesNotTrigger() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
    }

    func testDoublePressSchedulesFindMouse() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
        detector.registerRelease(at: 1.1)
        let action = detector.registerPress(at: 1.3)
        guard case .doubleTapPending(let token) = action else {
            return XCTFail("Expected a pending double tap")
        }

        XCTAssertTrue(detector.commitDoubleTap(token: token, at: 1.6))
    }

    func testSlowDoublePressDoesNotTrigger() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
        detector.registerRelease(at: 1.1)
        XCTAssertEqual(detector.registerPress(at: 1.7), .none)
    }

    // MARK: - Triple tap

    func testTriplePressCancelsFindMouseAndTriggersPresentationPointer() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
        detector.registerRelease(at: 1.1)
        let secondAction = detector.registerPress(at: 1.25)
        guard case .doubleTapPending(let token) = secondAction else {
            return XCTFail("Expected a pending double tap")
        }
        detector.registerRelease(at: 1.32)

        XCTAssertEqual(detector.registerPress(at: 1.5), .tripleTap)
        XCTAssertFalse(detector.commitDoubleTap(token: token, at: 1.55))
    }

    func testThirdPressOutsideTripleWindowLeavesDoubleTapPending() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
        detector.registerRelease(at: 1.1)
        let secondAction = detector.registerPress(at: 1.2)
        guard case .doubleTapPending(let token) = secondAction else {
            return XCTFail("Expected a pending double tap")
        }
        detector.registerRelease(at: 1.25)

        XCTAssertEqual(detector.registerPress(at: 1.51), .none)
        XCTAssertFalse(detector.commitDoubleTap(token: token, at: 1.52))
    }

    // MARK: - Boundaries and false positives

    func testPressWithoutReleaseDoesNotTrigger() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
        XCTAssertEqual(detector.registerPress(at: 1.2), .none)
    }

    func testExactlyAtDoubleTapWindowBoundarySchedules() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
        detector.registerRelease(at: 1.1)
        guard case .doubleTapPending = detector.registerPress(at: 1.5) else {
            return XCTFail("Expected boundary press to schedule")
        }
    }

    func testJustBeyondDoubleTapWindowDoesNotTrigger() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
        detector.registerRelease(at: 1.1)
        XCTAssertEqual(detector.registerPress(at: 1.51), .none)
    }

    func testReleaseAtSameInstantAsPressStillDoesNotAlternate() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
        detector.registerRelease(at: 1.0)
        XCTAssertEqual(detector.registerPress(at: 1.2), .none)
    }

    func testCommittedDoubleTapStartsCooldown() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
        detector.registerRelease(at: 1.1)
        guard case .doubleTapPending(let token) = detector.registerPress(at: 1.2) else {
            return XCTFail("Expected a pending double tap")
        }
        XCTAssertTrue(detector.commitDoubleTap(token: token, at: 1.5))
        detector.registerRelease(at: 1.6)

        XCTAssertEqual(detector.registerPress(at: 1.8), .none)
        detector.registerRelease(at: 1.9)
        XCTAssertEqual(detector.registerPress(at: 2.1), .none)
    }

    // MARK: - Reset

    func testResetClearsPendingState() {
        XCTAssertEqual(detector.registerPress(at: 1.0), .none)
        detector.registerRelease(at: 1.05)
        guard case .doubleTapPending(let token) = detector.registerPress(at: 1.2) else {
            return XCTFail("Expected a pending double tap")
        }

        detector.reset()
        XCTAssertFalse(detector.commitDoubleTap(token: token, at: 1.5))
    }

    // MARK: - Trigger key mapping

    func testTriggerKeyKeyCodesMatchHIDUsage() {
        XCTAssertEqual(FindMouseTriggerKey.leftControl.keyCode, 59)
        XCTAssertEqual(FindMouseTriggerKey.leftOption.keyCode, 58)
        XCTAssertEqual(FindMouseTriggerKey.leftCommand.keyCode, 55)
        XCTAssertEqual(FindMouseTriggerKey.leftShift.keyCode, 56)
        XCTAssertEqual(FindMouseTriggerKey.rightControl.keyCode, 62)
        XCTAssertEqual(FindMouseTriggerKey.rightOption.keyCode, 61)
        XCTAssertEqual(FindMouseTriggerKey.rightCommand.keyCode, 54)
        XCTAssertEqual(FindMouseTriggerKey.rightShift.keyCode, 60)
        XCTAssertEqual(FindMouseTriggerKey.function.keyCode, 63)
    }

    func testRecordedShortcutRoundTripsThroughSettingsValue() {
        let shortcut = FindMouseTriggerKey(
            keyCode: 46,
            modifiers: FindMouseTriggerKey.controlModifier | FindMouseTriggerKey.commandModifier,
            displayKey: "M"
        )

        XCTAssertEqual(FindMouseTriggerKey(rawValue: shortcut.rawValue), shortcut)
        XCTAssertEqual(FindMouseTriggerKey(rawValue: "leftControl"), .leftControl)
        XCTAssertNil(FindMouseTriggerKey(rawValue: "invalid"))
    }
}
