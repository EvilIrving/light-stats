//
//  MetricTrendSample.swift
//  Light Stats
//

import Foundation

/// 一次可持久化的趋势采样；按固定间隔保存，供下次启动恢复最近三小时折线。
struct MetricTrendSample: Codable, Sendable {
    let timestamp: Date
    let cpu: Double
    let memory: Double
    let gpu: Double
    let load: Double
    let networkUp: Double
    let networkDown: Double
}
