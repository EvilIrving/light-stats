//
//  HealthScoreServiceTests.swift
//  Light Stats Tests
//
//  Regression net for the pure, zero-dependency health-score computation.
//  Asserts the documented piecewise-linear knees, weight renormalization,
//  the bottleneck cap, EMA smoothing, and grade boundaries — against the
//  CODE's real thresholds (which the CLAUDE.md table summarizes loosely).
//

import XCTest
@testable import Light_Stats

final class HealthScoreServiceTests: XCTestCase {

    private typealias Toggles = HealthScoreService.DimensionToggles

    /// Neutral baseline: every dimension scores 100. Override one axis per test.
    private func compute(
        cpu: Double = 0,
        memoryPressure: MemoryPressureLevel = .normal,
        swap: Double = 0,
        load1: Double = 0,
        coreCount: Int = 8,
        temp: Double? = 20,
        thermal: ProcessInfo.ThermalState = .nominal,
        gpu: Double? = 0,
        batteryState: BatteryInfo.State = .charging,
        batteryPercent: Double = 100,
        diskIO: Double? = 0,
        toggles: Toggles = .all
    ) -> HealthScore {
        HealthScoreService.compute(
            cpu: cpu,
            memoryPressure: memoryPressure,
            swapActivityMBs: swap,
            load1: load1,
            coreCount: coreCount,
            temp: temp,
            thermalState: thermal,
            gpu: gpu,
            batteryState: batteryState,
            batteryPercent: batteryPercent,
            diskIO: diskIO,
            toggles: toggles
        )
    }

    private func only(
        cpu: Bool = false, memory: Bool = false, load: Bool = false,
        temperature: Bool = false, gpu: Bool = false, power: Bool = false
    ) -> Toggles {
        Toggles(cpu: cpu, memory: memory, load: load, temperature: temperature, gpu: gpu, power: power)
    }

    private func sub(_ score: HealthScore, _ dim: HealthScore.Dimension) -> Double {
        score.breakdown[dim.rawValue] ?? .nan
    }

    // MARK: - CPU dimension knees (warn 50, bad 85)

    func testCPUKnees() {
        let t = only(cpu: true)
        XCTAssertEqual(sub(compute(cpu: 0, toggles: t), .cpu), 100, accuracy: 0.001)
        XCTAssertEqual(sub(compute(cpu: 50, toggles: t), .cpu), 100, accuracy: 0.001)
        XCTAssertEqual(sub(compute(cpu: 67.5, toggles: t), .cpu), 80, accuracy: 0.001)  // mid 50–85
        XCTAssertEqual(sub(compute(cpu: 85, toggles: t), .cpu), 60, accuracy: 0.001)
        XCTAssertEqual(sub(compute(cpu: 92.5, toggles: t), .cpu), 30, accuracy: 0.001)  // mid 85–100
        XCTAssertEqual(sub(compute(cpu: 100, toggles: t), .cpu), 0, accuracy: 0.001)
    }

    // MARK: - Memory dimension (min of pressure score and swap-rate score)

    func testMemoryPressureLevels() {
        let t = only(memory: true)
        XCTAssertEqual(sub(compute(memoryPressure: .normal, toggles: t), .memory), 100, accuracy: 0.001)
        XCTAssertEqual(sub(compute(memoryPressure: .warning, toggles: t), .memory), 55, accuracy: 0.001)
        XCTAssertEqual(sub(compute(memoryPressure: .critical, toggles: t), .memory), 15, accuracy: 0.001)
    }

    func testMemorySwapRateKnees() {
        let t = only(memory: true)
        // Pressure normal (100), so the swap-rate score wins the min().
        XCTAssertEqual(sub(compute(swap: 1, toggles: t), .memory), 100, accuracy: 0.001)
        XCTAssertEqual(sub(compute(swap: 10.5, toggles: t), .memory), 80, accuracy: 0.001)   // mid 1–20
        XCTAssertEqual(sub(compute(swap: 20, toggles: t), .memory), 60, accuracy: 0.001)
        XCTAssertEqual(sub(compute(swap: 60, toggles: t), .memory), 30, accuracy: 0.001)     // mid 20–100
        XCTAssertEqual(sub(compute(swap: 100, toggles: t), .memory), 0, accuracy: 0.001)
        XCTAssertEqual(sub(compute(swap: 500, toggles: t), .memory), 0, accuracy: 0.001)     // clamps
    }

    func testMemoryTakesWorseOfPressureAndSwap() {
        let t = only(memory: true)
        // Warning pressure (55) vs heavy swap (score 0) -> min is 0.
        XCTAssertEqual(sub(compute(memoryPressure: .warning, swap: 100, toggles: t), .memory), 0, accuracy: 0.001)
    }

    // MARK: - Load dimension (per-core normalized, knees 0.7 / 1.0 / 2.0)

    func testLoadKnees() {
        let t = only(load: true)
        XCTAssertEqual(sub(compute(load1: 5.6, coreCount: 8, toggles: t), .load), 100, accuracy: 0.001)  // 0.7/core
        XCTAssertEqual(sub(compute(load1: 6.8, coreCount: 8, toggles: t), .load), 80, accuracy: 0.001)   // 0.85/core
        XCTAssertEqual(sub(compute(load1: 8, coreCount: 8, toggles: t), .load), 60, accuracy: 0.001)     // 1.0/core
        XCTAssertEqual(sub(compute(load1: 12, coreCount: 8, toggles: t), .load), 30, accuracy: 0.001)    // 1.5/core
        XCTAssertEqual(sub(compute(load1: 16, coreCount: 8, toggles: t), .load), 0, accuracy: 0.001)     // 2.0/core
        XCTAssertEqual(sub(compute(load1: 40, coreCount: 8, toggles: t), .load), 0, accuracy: 0.001)     // clamps
    }

    func testLoadWeightDoesNotDominateIdleCPU() {
        // LoadAvg can sit high on an idle Mac. Weight 8 keeps I/O-inflated load
        // from dominating the blend the way the old weight of 15 did.
        let t = only(cpu: true, load: true)
        // CPU idle (100) + 0.85/core load (80).
        // raw = (100*25 + 80*8) / 33 ≈ 95; cap 80+25 does not bind.
        let s = compute(cpu: 0, load1: 6.8, coreCount: 8, toggles: t)
        XCTAssertEqual(s.score, 95)
    }

    // MARK: - Temperature dimension (min of SMC temp score and thermal-state score)

    func testTemperatureKnees() {
        let t = only(temperature: true)
        XCTAssertEqual(sub(compute(temp: 60, toggles: t), .temperature), 100, accuracy: 0.001)
        XCTAssertEqual(sub(compute(temp: 72.5, toggles: t), .temperature), 80, accuracy: 0.001)  // mid 60–85
        XCTAssertEqual(sub(compute(temp: 85, toggles: t), .temperature), 60, accuracy: 0.001)
        XCTAssertEqual(sub(compute(temp: 100, toggles: t), .temperature), 0, accuracy: 0.001)
    }

    func testThermalStateFloorsTemperature() {
        let t = only(temperature: true)
        // Cool sensor (would be 100) but a hot thermal state pulls it down via min().
        XCTAssertEqual(sub(compute(temp: 20, thermal: .fair, toggles: t), .temperature), 80, accuracy: 0.001)
        XCTAssertEqual(sub(compute(temp: 20, thermal: .serious, toggles: t), .temperature), 45, accuracy: 0.001)
        XCTAssertEqual(sub(compute(temp: 20, thermal: .critical, toggles: t), .temperature), 10, accuracy: 0.001)
    }

    func testTemperatureFallsBackToThermalWhenSensorMissing() {
        let t = only(temperature: true)
        XCTAssertEqual(sub(compute(temp: nil, thermal: .serious, toggles: t), .temperature), 45, accuracy: 0.001)
    }

    // MARK: - GPU dimension knees (warn 70, bad 90)

    func testGPUKnees() {
        let t = only(gpu: true)
        XCTAssertEqual(sub(compute(gpu: 70, toggles: t), .gpu), 100, accuracy: 0.001)
        XCTAssertEqual(sub(compute(gpu: 80, toggles: t), .gpu), 80, accuracy: 0.001)  // mid 70–90
        XCTAssertEqual(sub(compute(gpu: 90, toggles: t), .gpu), 60, accuracy: 0.001)
        XCTAssertEqual(sub(compute(gpu: 95, toggles: t), .gpu), 30, accuracy: 0.001)  // mid 90–100
    }

    // MARK: - Power dimension: battery (laptop) vs disk I/O (desktop fallback)

    func testBatteryScore() {
        let t = only(power: true)
        // On AC (charging/charged) -> always full.
        XCTAssertEqual(sub(compute(batteryState: .charging, batteryPercent: 5, toggles: t), .battery), 100, accuracy: 0.001)
        // Discharging knees: >=40 full, 20–40 linear 60->100, <20 linear 0->60.
        XCTAssertEqual(sub(compute(batteryState: .discharging, batteryPercent: 40, toggles: t), .battery), 100, accuracy: 0.001)
        XCTAssertEqual(sub(compute(batteryState: .discharging, batteryPercent: 30, toggles: t), .battery), 80, accuracy: 0.001)
        XCTAssertEqual(sub(compute(batteryState: .discharging, batteryPercent: 20, toggles: t), .battery), 60, accuracy: 0.001)
        XCTAssertEqual(sub(compute(batteryState: .discharging, batteryPercent: 10, toggles: t), .battery), 30, accuracy: 0.001)
        XCTAssertEqual(sub(compute(batteryState: .discharging, batteryPercent: 0, toggles: t), .battery), 0, accuracy: 0.001)
    }

    func testDiskIOFallbackWhenNoBattery() {
        let t = only(power: true)
        // No battery -> the power dimension falls back to disk I/O MB/s.
        let s = compute(batteryState: .noBattery, diskIO: 100, toggles: t)
        XCTAssertEqual(sub(s, .diskIO), 80, accuracy: 0.001)              // mid 50–150
        XCTAssertNil(s.breakdown[HealthScore.Dimension.battery.rawValue])
        XCTAssertEqual(sub(compute(batteryState: .noBattery, diskIO: 150, toggles: t), .diskIO), 60, accuracy: 0.001)
        XCTAssertEqual(sub(compute(batteryState: .noBattery, diskIO: 300, toggles: t), .diskIO), 0, accuracy: 0.001)
    }

    func testNoBatteryAndNoDiskIODropsPowerDimension() {
        let s = compute(batteryState: .noBattery, diskIO: nil, toggles: only(power: true))
        // Nothing contributes -> renormalizes to perfect.
        XCTAssertEqual(s, .perfect)
    }

    // MARK: - Weight renormalization

    func testAllDimensionsOffIsPerfect() {
        let s = compute(cpu: 100, memoryPressure: .critical, load1: 99, temp: 99, gpu: 99,
                        toggles: only())  // everything off
        XCTAssertEqual(s, .perfect)
    }

    func testRenormalizationAcrossTwoDimensions() {
        // CPU=100 (score 100, weight 25) + GPU=90 (score 60, weight 15).
        // raw = (100*25 + 60*15) / 40 = 85. Cap (worst 60 + 25 = 85) does not bind.
        let s = compute(cpu: 0, gpu: 90, toggles: only(cpu: true, gpu: true))
        XCTAssertEqual(s.score, 85)
    }

    // MARK: - Bottleneck cap (single saturated performance dim drags the total)

    func testBottleneckCapAppliesToPerformanceDimensions() {
        // CPU 100 + memory 100 + load 0. Weighted avg is high, but a saturated
        // performance dimension caps the total at worst(0) + 25 = 25.
        let s = compute(cpu: 0, memoryPressure: .normal, load1: 99, coreCount: 8,
                        toggles: only(cpu: true, memory: true, load: true))
        XCTAssertEqual(s.score, 25)
    }

    func testPowerDimensionIsExcludedFromBottleneckCap() {
        // CPU 100 (perf) + empty battery 0 (power). Power must NOT cap the total.
        // raw = (100*25 + 0*10)/35 ≈ 71.4; worst PERF dim is cpu=100 -> no cap.
        let s = compute(cpu: 0, batteryState: .discharging, batteryPercent: 0,
                        toggles: only(cpu: true, power: true))
        XCTAssertEqual(s.score, 71)
        XCTAssertGreaterThan(s.score, 25)  // would be 25 if power counted toward the cap
    }

    // MARK: - EMA smoothing (alpha 0.35)

    func testSmoothBlendsTowardCurrentByAlpha() {
        let previous = HealthScore(score: 100, grade: .excellent, breakdown: [:])
        let current = HealthScore(score: 0, grade: .critical, breakdown: [:])
        // 100*(1-0.35) + 0*0.35 = 65.
        XCTAssertEqual(HealthScoreService.smooth(current: current, previous: previous).score, 65)
    }

    func testSmoothWithoutPreviousReturnsCurrent() {
        let current = HealthScore(score: 42, grade: .poor, breakdown: ["cpu": 42])
        XCTAssertEqual(HealthScoreService.smooth(current: current, previous: nil), current)
    }

    func testSmoothConvergesTowardCurrent() {
        let target = HealthScore(score: 0, grade: .critical, breakdown: [:])
        var value = HealthScore(score: 100, grade: .excellent, breakdown: [:])
        var previousScore = value.score
        for _ in 0..<20 {
            value = HealthScoreService.smooth(current: target, previous: value)
            XCTAssertLessThanOrEqual(value.score, previousScore)  // monotonic descent
            previousScore = value.score
        }
        XCTAssertLessThan(value.score, 5)  // approached the target
    }

    // MARK: - Grade boundaries

    func testGradeBoundaries() {
        XCTAssertEqual(HealthScoreService.grade(for: 100), .excellent)
        XCTAssertEqual(HealthScoreService.grade(for: 90), .excellent)
        XCTAssertEqual(HealthScoreService.grade(for: 89), .good)
        XCTAssertEqual(HealthScoreService.grade(for: 75), .good)
        XCTAssertEqual(HealthScoreService.grade(for: 74), .fair)
        XCTAssertEqual(HealthScoreService.grade(for: 60), .fair)
        XCTAssertEqual(HealthScoreService.grade(for: 59), .poor)
        XCTAssertEqual(HealthScoreService.grade(for: 40), .poor)
        XCTAssertEqual(HealthScoreService.grade(for: 39), .critical)
        XCTAssertEqual(HealthScoreService.grade(for: 0), .critical)
    }
}
