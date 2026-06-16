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
/// - 内存看 **内存压力 + 换页速率**（macOS 内存常年 80%+，使用率并不能反映健康；速率比 swap 占用量更诚实）
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
        static let gpu = 15.0
        // 电源维度：电池电量（笔记本）或磁盘 I/O（台式机回退），共用同一权重
        static let battery = 10.0
        static let diskIO = 10.0
    }

    /// 各维度是否参与健康分计算（设置项可逐项开关）。
    /// `power` 同时控制电池（笔记本）/磁盘 I/O（台式机）这一硬件二选一的电源维度。
    struct DimensionToggles: Sendable {
        var cpu = true
        var memory = true
        var load = true
        var temperature = true
        var gpu = true
        var power = true

        static let all = DimensionToggles()
    }

    static let smoothingAlpha = 0.35

    /// 瓶颈封顶余量：总分不得高于「最差性能维度得分 + 该值」。
    static let bottleneckHeadroom = 25.0

    /// 参与瓶颈封顶的性能维度（真正影响流畅度的项；电源维度不算卡顿来源）。
    private static let performanceDimensions: Set<HealthScore.Dimension> = [.cpu, .memory, .load, .temperature, .gpu]

    // swiftlint:disable:next function_parameter_count
    static func compute(
        cpu: Double,
        memoryPressure: MemoryPressureLevel,
        swapActivityMBs: Double,
        load1: Double,
        coreCount: Int,
        temp: Double?,
        thermalState: ProcessInfo.ThermalState,
        gpu: Double?,
        batteryState: BatteryInfo.State,
        batteryPercent: Double,
        diskIO: Double?,
        toggles: DimensionToggles = .all
    ) -> HealthScore {
        var inputs: [DimensionInput] = []

        if toggles.cpu {
            inputs.append(DimensionInput(dimension: .cpu, weight: Weight.cpu, score: usageScore(cpu, warn: 50, bad: 85)))
        }
        if toggles.memory {
            inputs.append(DimensionInput(
                dimension: .memory,
                weight: Weight.memory,
                score: memoryScore(pressure: memoryPressure, swapActivityMBs: swapActivityMBs)
            ))
        }
        if toggles.load {
            inputs.append(DimensionInput(
                dimension: .load,
                weight: Weight.load,
                score: loadScore(load1: load1, coreCount: coreCount)
            ))
        }
        if toggles.temperature {
            // 温度维度：热状态（降频信号）随时可读，与 SMC 温度取较低值。
            inputs.append(DimensionInput(
                dimension: .temperature,
                weight: Weight.temperature,
                score: temperatureScore(temp: temp, thermalState: thermalState)
            ))
        }
        if toggles.gpu, let gpu {
            inputs.append(DimensionInput(dimension: .gpu, weight: Weight.gpu, score: gpuScore(gpu)))
        }

        // 电源维度：笔记本用电池电量，台式机（无电池）回退到磁盘 I/O。
        if toggles.power {
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
        }

        let totalWeight = inputs.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return .perfect }

        let weightedScore = inputs.reduce(0) { partial, input in
            partial + input.score * (input.weight / totalWeight)
        }

        // 瓶颈封顶：单一性能维度（CPU/内存/负载/温度/GPU）拖垮体验时，加权平均会把它稀释掉，
        // 但用户感知到的就是「卡」。所以总分不得高于「最差性能维度 + headroom」。
        // 电池/磁盘 I/O 不是卡顿来源，不参与封顶。
        let worstPerf = inputs
            .filter { performanceDimensions.contains($0.dimension) }
            .map(\.score)
            .min() ?? 100
        let cap = worstPerf + bottleneckHeadroom
        let cappedScore = Swift.min(weightedScore, cap)
        let roundedScore = Int(clamp(cappedScore, min: 0, max: 100).rounded())
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

    /// GPU 健康：利用率越高越扣分。日常 GPU 多为个位数，仅持续高占用才明显扣分。
    /// ≤70% 满分，70→90% 降到 60，90%+ 趋 0。
    private static func gpuScore(_ value: Double) -> Double {
        usageScore(value, warn: 70, bad: 90)
    }

    /// 温度健康：SMC 温度与系统热状态取较低值。热状态反映内核是否已在降频，
    /// 是「卡顿」最直接的信号；温度缺失（无 SMC 读数）时仅看热状态。
    private static func temperatureScore(temp: Double?, thermalState: ProcessInfo.ThermalState) -> Double {
        let thermal = thermalScore(thermalState)
        guard let temp else { return thermal }
        return Swift.min(usageScore(temp, warn: 60, bad: 85), thermal)
    }

    private static func thermalScore(_ state: ProcessInfo.ThermalState) -> Double {
        switch state {
        case .nominal: return 100
        case .fair: return 80
        case .serious: return 45
        case .critical: return 10
        @unknown default: return 100
        }
    }

    /// 内存健康：以 macOS 内存压力等级为主、**换页速率**（磁盘 swap MB/s）为辅，取两者较低值。
    /// 内存压力是系统权威信号；换页速率反映此刻是否正在颠簸——
    /// 比 swap 占用量更诚实：占用量在压力消退后仍滞留，会对一台当下流畅的机器误扣分。
    private static func memoryScore(pressure: MemoryPressureLevel, swapActivityMBs: Double) -> Double {
        let levelScore: Double
        switch pressure {
        case .normal: levelScore = 100
        case .warning: levelScore = 55
        case .critical: levelScore = 15
        }

        // 换页速率打分：≤1 MB/s 视为静止（满分），1–20 线性降到 60，20–100 继续降到 0。
        let rate = Swift.max(0, swapActivityMBs)
        let swapScore: Double
        if rate <= 1 {
            swapScore = 100
        } else if rate <= 20 {
            swapScore = interpolate(value: rate, from: 1, to: 20, start: 100, end: 60)
        } else {
            swapScore = interpolate(value: rate, from: 20, to: 100, start: 60, end: 0)
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
