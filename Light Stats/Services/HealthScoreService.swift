//
//  HealthScoreService.swift
//  Light Stats
//
//  Created on 2026/06/07.
//

import Foundation

/// 健康分纯计算服务：按 Mole 风格从满分向下扣，缺失可选维度时自动重分配权重。
nonisolated enum HealthScoreService {
    private struct DimensionInput {
        let dimension: HealthScore.Dimension
        let weight: Double
        let score: Double
    }

    private enum Weight {
        static let cpu = 30.0
        static let memory = 25.0
        static let disk = 20.0
        static let temperature = 15.0
        static let diskIO = 10.0
    }

    static let smoothingAlpha = 0.35

    static func compute(cpu: Double, mem: Double, disk: Double, temp: Double?, diskIO: Double?) -> HealthScore {
        var inputs: [DimensionInput] = [
            DimensionInput(dimension: .cpu, weight: Weight.cpu, score: usageScore(cpu, warn: 30, bad: 70)),
            DimensionInput(dimension: .memory, weight: Weight.memory, score: usageScore(mem, warn: 50, bad: 80)),
            DimensionInput(dimension: .disk, weight: Weight.disk, score: usageScore(disk, warn: 70, bad: 90))
        ]

        if let temp {
            inputs.append(DimensionInput(
                dimension: .temperature,
                weight: Weight.temperature,
                score: usageScore(temp, warn: 60, bad: 85)
            ))
        }

        if let diskIO {
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

    private static func usageScore(_ value: Double, warn: Double, bad: Double) -> Double {
        let value = clamp(value, min: 0, max: 100)
        if value <= warn { return 100 }
        if value <= bad {
            return interpolate(value: value, from: warn, to: bad, start: 100, end: 60)
        }
        return interpolate(value: value, from: bad, to: 100, start: 60, end: 0)
    }

    private static func ioScore(_ value: Double) -> Double {
        let value = max(0, value)
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
