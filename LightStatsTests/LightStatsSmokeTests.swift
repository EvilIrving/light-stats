//  LightStatsTests.swift
//  Light Stats Tests
//
//  Smoke tests — validates core model types and services compile & behave correctly.
//  To add to Xcode: File → New → Target → Unit Testing Bundle → name "LightStatsTests".
//  CI runs: xcodebuild test -project "Light Stats.xcodeproj" -scheme "Light Stats" -destination 'platform=macOS'
//  (requires the test target added to the Xcode project once).

import XCTest
@testable import Light_Stats

final class LightStatsSmokeTests: XCTestCase {

    // MARK: - Models

    func testCPUInfoDefault() {
        let cpu = CPUInfo()
        XCTAssertEqual(cpu.usage, 0)
        XCTAssertEqual(cpu.cores, 0)
    }

    func testMemoryInfoDefault() {
        let mem = MemoryInfo()
        XCTAssertEqual(mem.used, 0)
        XCTAssertEqual(mem.total, 0)
    }

    func testBatteryInfoDefault() {
        let bat = BatteryInfo()
        XCTAssertFalse(bat.isPresent)
        XCTAssertEqual(bat.charge, 0)
    }

    func testDiskInfoDefault() {
        let disk = DiskInfo()
        XCTAssertEqual(disk.used, 0)
        XCTAssertEqual(disk.total, 0)
    }

    func testGPUInfoDefault() {
        let gpu = GPUInfo()
        XCTAssertEqual(gpu.usage, 0)
    }

    func testNetworkInfoDefault() {
        let net = NetworkInfo()
        XCTAssertEqual(net.downloadSpeed, 0)
        XCTAssertEqual(net.uploadSpeed, 0)
    }

    func testProxyInfoDefault() {
        let proxy = ProxyInfo()
        XCTAssertFalse(proxy.isActive)
    }

    func testHealthScoreRange() {
        let score = HealthScore()
        XCTAssertGreaterThanOrEqual(score.value, 0)
        XCTAssertLessThanOrEqual(score.value, 100)
    }

    func testProcessStatsDefault() {
        let proc = ProcessStats()
        XCTAssertEqual(proc.totalCPU, 0)
        XCTAssertTrue(proc.topProcesses.isEmpty)
    }

    func testAIUsageInfoDefault() {
        let ai = AIUsageInfo()
        XCTAssertFalse(ai.isAvailable)
    }

    func testCoreTypeIsHashable() {
        let core = CoreType.performance
        _ = core.hashValue  // compiles = confirmed Hashable
    }

    func testAppGroupDefault() {
        let group = AppGroup(label: "Test", processes: [])
        XCTAssertEqual(group.label, "Test")
        XCTAssertTrue(group.processes.isEmpty)
    }

    // MARK: - Utilities

    func testByteFormatterCompact() {
        XCTAssertEqual(ByteFormatter.format(bytes: 0), "0 B")
        XCTAssertEqual(ByteFormatter.format(bytes: 1024), "1.0 KB")
    }

    func testByteFormatterIsIdempotent() {
        let a = ByteFormatter.format(bytes: 1_073_741_824)
        let b = ByteFormatter.format(bytes: 1_073_741_824)
        XCTAssertEqual(a, b)
    }

    // MARK: - ViewModel existence

    func testSettingsManagerExists() {
        _ = SettingsManager()
        // Defaults must load without crashing
    }
}
