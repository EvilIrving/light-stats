//
//  HealthScoreService.swift
//  Light Stats
//
//  Created on 2026/06/07.
//

import Foundation

/// 健康分纯计算服务：按 Mole 风格从满分向下扣，缺失可选维度时自动重分配权重。
///
/// 维度选取偏向「此刻系统卡不卡」的实时压力信号，而非缓变的容量数字：
/// - 内存看 **内存压力 + swap**（macOS 内存常年 80%+，使用率并不能反映健康）
/// - CPU 看持续负载，并辅以系统 **LoadAvg**（排队等 CPU 的进程数）
/// - 温度反映热节流风险
/// - 第 5 维：笔记本看 **电池电量**（电量过低也是一种系统风险）；台式机无电池时回退到 **磁盘 I/O**
/// 磁盘使用率已移除（缓变的容量告警，不该混入实时健康分）。
nonisolated enum HealthScoreService {
    private struct DimensionInput {
        let dimension: HealthScore.Dimension
        let weight: Double
        let score: Double
    }

    private enum Weight {
        static let cpu = 25.0
        static let memory = 30.0
        static let load = 15.0
        static let temperature = 20.0
        // 第 5 维：电池电量（笔记本）或磁盘 I/O（台式机回退），共用同一权重
        static let battery = 10.0
        static let diskIO = 10.0
    }

    static let smoothingAlpha = 0.35

    static func compute(
        cpu: Double,
        memoryPressure: MemoryPressureLevel,
        swapUsed: UInt64,
        physicalMemory: UInt64,
        load1: Double,
        coreCount: Int,
        temp: Double?,
        batteryState: BatteryInfo.State,
        batteryPercent: Double,
        diskIO: Double?
    ) -> HealthScore {
        var inputs: [DimensionInput] = [
            DimensionInput(dimension: .cpu, weight: Weight.cpu, score: usageScore(cpu, warn: 50, bad: 85)),
            DimensionInput(
                dimension: .memory,
                weight: Weight.memory,
                score: memoryScore(pressure: memoryPressure, swapUsed: swapUsed, physicalMemory: physicalMemory)
            ),
            DimensionInput(
                dimension: .load,
                weight: Weight.load,
                score: loadScore(load1: load1, coreCount: coreCount)
            )
        ]

        if let temp {
            inputs.append(DimensionInput(
                dimension: .temperature,
                weight: Weight.temperature,
                score: usageScore(temp, warn: 60, bad: 85)
            ))
        }

        // 笔记本用电池电量作第 5 维；台式机（无电池）回退到磁盘 I/O。
        if batteryState != .noBattery {
            inputs.append(DimensionInput(
                dimension: .battery,
                weight: Weight.battery,
                score: batteryScore(state: batteryState, percent: batteryPercent)
            ))
        } else if let diskIO {
            inputs.append(DimensionInput(
                dimension: .diskIO,
                weight: Weight.diskIO,
                score: ioScore(diskIO)
            ))
        }

        let totalWeight = inputs.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return .perfect }

        let weightedScore = inputs.reduce(0) { partial, input in
            partial + input.score * (input.weight / totalWeight)
        }
        let roundedScore = Int(clamp(weightedScore, min: 0, max: 100).rounded())
        let breakdown = Dictionary(uniqueKeysWithValues: inputs.map { ($0.dimension.rawValue, $0.score) })

        return HealthScore(score: roundedScore, grade: grade(for: roundedScore), breakdown: breakdown)
    }

    static func smooth(current: HealthScore, previous: HealthScore?, alpha: Double = smoothingAlpha) -> HealthScore {
        guard let previous else { return current }
        let clampedAlpha = clamp(alpha, min: 0, max: 1)
        let smoothedScore = Double(previous.score) * (1 - clampedAlpha) + Double(current.score) * clampedAlpha
        let score = Int(clamp(smoothedScore, min: 0, max: 100).rounded())
        return HealthScore(score: score, grade: grade(for: score), breakdown: current.breakdown)
    }

    static func grade(for score: Int) -> HealthScore.Grade {
        switch score {
        case 90...100:
            return .excellent
        case 75..<90:
            return .good
        case 60..<75:
            return .fair
        case 40..<60:
            return .poor
        default:
            return .critical
        }
    }

    // MARK: - Per-dimension scoring

    private static func usageScore(_ value: Double, warn: Double, bad: Double) -> Double {
        let value = clamp(value, min: 0, max: 100)
        if value <= warn { return 100 }
        if value <= bad {
            return interpolate(value: value, from: warn, to: bad, start: 100, end: 60)
        }
        return interpolate(value: value, from: bad, to: 100, start: 60, end: 0)
    }

    /// 内存健康：以 macOS 内存压力等级为主、swap 占物理内存比例为辅，取两者较低值。
    /// 内存压力是系统权威信号，swap 大量使用意味着真实的换页颠簸。
    private static func memoryScore(pressure: MemoryPressureLevel, swapUsed: UInt64, physicalMemory: UInt64) -> Double {
        let levelScore: Double
        switch pressure {
        case .normal: levelScore = 100
        case .warning: levelScore = 55
        case .critical: levelScore = 15
        }

        let swapRatio = physicalMemory > 0 ? Double(swapUsed) / Double(physicalMemory) * 100 : 0
        let swapScore: Double
        if swapRatio <= 2 {
            swapScore = 100
        } else if swapRatio <= 10 {
            swapScore = interpolate(value: swapRatio, from: 2, to: 10, start: 100, end: 60)
        } else {
            swapScore = interpolate(value: swapRatio, from: 10, to: 25, start: 60, end: 0)
        }

        return Swift.min(levelScore, swapScore)
    }

    /// 系统负载健康：以单核归一化的 1 分钟 LoadAvg 衡量「排队等 CPU」的程度。
    /// 每核 ≤0.7 视为健康，>1.0 表示核心持续饱和、进程开始排队。
    private static func loadScore(load1: Double, coreCount: Int) -> Double {
        let perCore = coreCount > 0 ? load1 / Double(coreCount) : load1
        if perCore <= 0.7 { return 100 }
        if perCore <= 1.0 {
            return interpolate(value: perCore, from: 0.7, to: 1.0, start: 100, end: 60)
        }
        return interpolate(value: perCore, from: 1.0, to: 2.0, start: 60, end: 0)
    }

    /// 电池电量：接通电源（充电/已充满）视为满分；放电时电量越低风险越高。
    /// ≥40% 满分，20–40% 线性降到 60，<20% 继续降到 0。
    private static func batteryScore(state: BatteryInfo.State, percent: Double) -> Double {
        if state == .charging || state == .charged { return 100 }
        let value = clamp(percent, min: 0, max: 100)
        if value >= 40 { return 100 }
        if value >= 20 {
            return interpolate(value: value, from: 20, to: 40, start: 60, end: 100)
        }
        return interpolate(value: value, from: 0, to: 20, start: 0, end: 60)
    }

    /// 磁盘 I/O（台式机回退维度）：读写合计 MB/s，≤50 满分，150 起明显繁忙，300 触底。
    private static func ioScore(_ value: Double) -> Double {
        let value = Swift.max(0, value)
        if value <= 50 { return 100 }
        if value <= 150 {
            return interpolate(value: value, from: 50, to: 150, start: 100, end: 60)
        }
        return interpolate(value: value, from: 150, to: 300, start: 60, end: 0)
    }

    private static func interpolate(value: Double, from: Double, to: Double, start: Double, end: Double) -> Double {
        guard to > from else { return end }
        let progress = clamp((value - from) / (to - from), min: 0, max: 1)
        return start + (end - start) * progress
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}
