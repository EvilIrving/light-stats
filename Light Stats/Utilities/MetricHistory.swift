//
//  MetricHistory.swift
//  Light Stats
//
//  Created on 2026/06/23.
//

import Foundation

/// 定长环形缓冲：按时间顺序保存最近 `capacity` 个采样点，超出时丢弃最旧。
/// App-agnostic value storage —— 不感知任何指标语义，仅做先进先出的数值序列。
struct MetricHistory: Sendable {
    /// 按时间从旧到新排列的取值（最多 `capacity` 个）。
    private(set) var values: [Double]
    let capacity: Int

    init(capacity: Int = 60) {
        self.capacity = max(1, capacity)
        self.values = []
        values.reserveCapacity(self.capacity)
    }

    /// 追加一个采样点，必要时丢弃最旧的一个以维持定长。
    mutating func push(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }
}
