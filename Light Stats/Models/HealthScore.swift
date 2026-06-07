//
//  HealthScore.swift
//  Light Stats
//
//  Created on 2026/06/07.
//

import Foundation

/// 系统健康分总览。`breakdown` 存各维度 0-100 子分，key 使用 `HealthScore.Dimension.rawValue`。
nonisolated struct HealthScore: Sendable, Equatable {
    enum Grade: Sendable {
        case excellent
        case good
        case fair
        case poor
        case critical
    }

    enum Dimension: String, CaseIterable, Sendable {
        case cpu
        case memory
        case disk
        case temperature
        case diskIO
    }

    var score: Int
    var grade: Grade
    var breakdown: [String: Double]

    static let perfect = HealthScore(
        score: 100,
        grade: .excellent,
        breakdown: [:]
    )
}
