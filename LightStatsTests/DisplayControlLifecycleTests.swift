//
//  DisplayControlLifecycleTests.swift
//  Light Stats Tests
//

import CoreGraphics
import XCTest
@testable import Light_Stats

@MainActor
final class DisplayControlLifecycleTests: XCTestCase {
    func testEnvironmentGateSuppressesSleepAndWakeSettleWindow() async throws {
        let gate = DDCEnvironmentGate(wakeDelay: 0.03, reconfigureDelay: 0.03)
        XCTAssertFalse(gate.isSuppressed)

        gate.handleWillSleep()
        XCTAssertTrue(gate.isSuppressed)

        gate.handleDidWake()
        XCTAssertTrue(gate.isSuppressed)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(gate.isSuppressed)
    }

    func testEnvironmentGateUsesSafetyTimeoutForIncompleteReconfiguration() async throws {
        let gate = DDCEnvironmentGate(reconfigureSafetyDelay: 0.03)
        gate.handleReconfigure(flags: .beginConfigurationFlag)
        XCTAssertTrue(gate.isSuppressed)

        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(gate.isSuppressed)
    }

    func testEnvironmentGateSettlesAfterCompletedReconfiguration() async throws {
        let gate = DDCEnvironmentGate(reconfigureDelay: 0.03)
        gate.handleReconfigure(flags: .beginConfigurationFlag)
        gate.handleReconfigure(flags: .setModeFlag)
        XCTAssertTrue(gate.isSuppressed)

        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(gate.isSuppressed)
    }

    func testWriteDebouncerKeepsOnlyLatestValuePerDisplay() async throws {
        let debouncer = DisplayWriteDebouncer(delay: .milliseconds(20))
        var writtenValues: [Double] = []

        debouncer.submit(displayID: 1, value: 20) { value in
            writtenValues.append(value)
        }
        debouncer.submit(displayID: 1, value: 40) { value in
            writtenValues.append(value)
        }
        debouncer.submit(displayID: 1, value: 75) { value in
            writtenValues.append(value)
        }

        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(writtenValues, [75])
    }

    func testWriteDebouncerKeepsDisplaysIndependent() async throws {
        let debouncer = DisplayWriteDebouncer(delay: .milliseconds(20))
        var writtenValues: [UInt32: Double] = [:]

        debouncer.submit(displayID: 1, value: 25) { value in
            writtenValues[1] = value
        }
        debouncer.submit(displayID: 2, value: 80) { value in
            writtenValues[2] = value
        }

        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(writtenValues, [1: 25, 2: 80])
    }
}
