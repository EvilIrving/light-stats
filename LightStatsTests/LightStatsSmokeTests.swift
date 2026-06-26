//
//  LightStatsSmokeTests.swift
//  Light Stats Tests
//
//  Smoke tests — a thin "does the test bundle link against the app and can it
//  touch real types" check. Substantive coverage lives in the dedicated
//  HealthScoreServiceTests / SettingsDefaultsTests / AIUsageParsingTests files.
//

import XCTest
@testable import Light_Stats

final class LightStatsSmokeTests: XCTestCase {

    // MARK: - Model sentinels

    func testBatteryNoBatterySentinel() {
        XCTAssertEqual(BatteryInfo.noBattery.state, .noBattery)
    }

    func testProxyConfigNoneIsDisabled() {
        XCTAssertFalse(ProxyConfig.none.isEnabled)
    }

    func testDiskIOZero() {
        XCTAssertEqual(DiskIOStats.zero.readMBs, 0)
        XCTAssertEqual(DiskIOStats.zero.writeMBs, 0)
    }

    func testHealthScorePerfect() {
        XCTAssertEqual(HealthScore.perfect.score, 100)
        XCTAssertEqual(HealthScore.perfect.grade, .excellent)
    }

    func testAIProviderHasThreeCases() {
        XCTAssertEqual(Set(AIProvider.allCases), [.claude, .codex, .gemini])
    }

    // MARK: - Utilities

    func testByteFormatterProducesNonEmptyDeterministicOutput() {
        XCTAssertFalse(ByteFormatter.format(0).isEmpty)
        let a = ByteFormatter.format(1_073_741_824)
        let b = ByteFormatter.format(1_073_741_824)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.contains("GB"), "1 GiB should format with a GB unit, got \(a)")
    }

    func testDiskFormatterRoundsUp() {
        XCTAssertEqual(ByteFormatter.formatDisk(1_500_000_000), "2 GB")
    }
}
