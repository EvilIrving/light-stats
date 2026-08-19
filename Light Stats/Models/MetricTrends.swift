//
//  MetricTrends.swift
//  Light Stats
//
//  Created on 2026/06/23.
//

import Foundation

/// 各指标最近一段时间的取值序列快照，供弹窗里的 sparkline 折线读取。
/// 纯数据：从旧到新排列，长度由 `SystemMonitor` 的绘图缓存决定。
struct MetricTrends: Sendable {
    var cpu: [Double] = []
    var memory: [Double] = []
    var gpu: [Double] = []
    /// 负载占用百分比（load1 ÷ 核心数，封顶 100）。
    var load: [Double] = []
    /// 上行速率，单位 bytes/s。
    var networkUp: [Double] = []
    /// 下行速率，单位 bytes/s。
    var networkDown: [Double] = []

    static let empty = MetricTrends()
}
