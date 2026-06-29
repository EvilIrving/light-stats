//
//  BatteryInfo.swift
//  Light Stats
//
//  Created on 2026/06/07.
//
//  电池/功耗模型：电量、充放电状态、剩余时间、循环次数、健康度、实时功耗、温度。
//  数据来自 IOKit（IOPowerSources + AppleSmartBattery），见 `PowerService`。
//

import Foundation

/// 一次电池采集的快照。无电池机型（台式 Mac）`state = .noBattery`，其余字段 nil。
/// 纯数据模型标 `nonisolated` + `Sendable`：可在采集 actor 上构造、跨 actor 回主线程绑定视图。
nonisolated struct BatteryInfo: Sendable, Equatable {
    enum State: Sendable {
        case charging
        case discharging
        case charged
        /// 已接电源但未在充电：常见于电量保护（如停在 80%）或系统暂停充电。
        case acNotCharging
        case noBattery
    }

    var state: State
    /// 0–100。无电池时为 0。
    var percent: Double
    /// 剩余/充满分钟数；计算中或未知为 nil。
    var timeRemaining: Int?
    var cycleCount: Int?
    /// 最大容量 / 设计容量，0–100。
    var healthPercent: Int?
    /// 电池状态正常与否（best-effort，取不到为 nil）。
    var conditionOK: Bool?
    /// 实时功耗（W）。取不到或数值异常为 nil（避免溢出脏值）。
    var powerWatts: Double?
    /// 电池温度（°C）。
    var temperature: Double?

    /// 无电池占位值（台式 Mac / 读取失败）。
    static let noBattery = BatteryInfo(
        state: .noBattery, percent: 0, timeRemaining: nil,
        cycleCount: nil, healthPercent: nil, conditionOK: nil,
        powerWatts: nil, temperature: nil
    )
}
