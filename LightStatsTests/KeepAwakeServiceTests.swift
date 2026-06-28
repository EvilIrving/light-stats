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

import XCTest
@testable import Light_Stats

@MainActor
final class KeepAwakeServiceTests: XCTestCase {

    override func tearDown() {
        KeepAwakeService.shared.stop()
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
}
