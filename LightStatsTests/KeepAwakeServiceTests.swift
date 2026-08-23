//
//  KeepAwakeServiceTests.swift
//  LightStatsTests
//
//  Created on 2026/06/28.
//
//  Exercises the IOPM power-assertion lifecycle: start succeeds and is idempotent,
//  stop releases, and the running flag tracks state. Holds a real assertion only
//  for the duration of the test (released in tearDown).
//

import CoreGraphics
import IOKit.ps
import XCTest
@testable import Light_Stats

@MainActor
final class KeepAwakeServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Never spawn a WindowServer virtual display from XCTest.
        KeepAwakeService.shared.usesClamshellDisplay = false
        KeepAwakeService.shared.stop()
    }

    override func tearDown() {
        KeepAwakeService.shared.stop()
        KeepAwakeService.shared.usesClamshellDisplay = true
        super.tearDown()
    }

    func testStartHoldsAssertionAndIsIdempotent() {
        let service = KeepAwakeService.shared
        XCTAssertFalse(service.isRunning)

        XCTAssertTrue(service.start())
        XCTAssertTrue(service.isRunning)

        // Second start is a no-op that still reports success.
        XCTAssertTrue(service.start())
        XCTAssertTrue(service.isRunning)

        // The assertion is real and visible to the system (verified manually via
        // `pmset -g assertions` → `PreventUserIdleDisplaySleep … "Light Stats keep awake"`).
    }

    func testStopReleasesAssertion() {
        let service = KeepAwakeService.shared
        XCTAssertTrue(service.start())
        service.stop()
        XCTAssertFalse(service.isRunning)

        // Stop again is harmless.
        service.stop()
        XCTAssertFalse(service.isRunning)
    }

    func testClamshellDisplayOnlyWhenPortableOnACWithoutExternal() {
        XCTAssertTrue(
            KeepAwakeService.needsClamshellDisplay(
                isPortable: true, onAC: true, hasForeignExternal: false
            )
        )
        XCTAssertFalse(
            KeepAwakeService.needsClamshellDisplay(
                isPortable: true, onAC: false, hasForeignExternal: false
            )
        )
        XCTAssertFalse(
            KeepAwakeService.needsClamshellDisplay(
                isPortable: true, onAC: true, hasForeignExternal: true
            )
        )
        XCTAssertFalse(
            KeepAwakeService.needsClamshellDisplay(
                isPortable: false, onAC: true, hasForeignExternal: false
            )
        )
    }

    func testDisplaySyncSkipsBeginConfiguration() {
        let begin = CGDisplayChangeSummaryFlags(rawValue: 1 << 0)
        let add = CGDisplayChangeSummaryFlags(rawValue: 1 << 4)
        XCTAssertFalse(KeepAwakeService.shouldSyncAfterDisplayChange(begin))
        XCTAssertFalse(KeepAwakeService.shouldSyncAfterDisplayChange([begin, add]))
        XCTAssertTrue(KeepAwakeService.shouldSyncAfterDisplayChange(add))
        XCTAssertTrue(KeepAwakeService.shouldSyncAfterDisplayChange([]))
    }

    func testMissingPowerSourceIsNotTreatedAsAC() {
        XCTAssertFalse(KeepAwakeService.isOnACPower(batteryPowerState: nil))
        XCTAssertFalse(KeepAwakeService.isOnACPower(batteryPowerState: kIOPSBatteryPowerValue))
        XCTAssertTrue(KeepAwakeService.isOnACPower(batteryPowerState: kIOPSACPowerValue))
    }
}
