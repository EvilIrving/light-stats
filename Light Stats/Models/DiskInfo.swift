//
//  DiskInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation

/// 磁盘读/写速率（MB/s）。差值法采集，见 `DiskIOService`。
/// 纯数据模型标 `nonisolated` + `Sendable`：跨采集 actor → 主线程安全。
nonisolated struct DiskIOStats: Sendable, Equatable {
    var readMBs: Double
    var writeMBs: Double

    static let zero = DiskIOStats(readMBs: 0, writeMBs: 0)
}

enum DiskInfo {

    struct Info {
        let total: UInt64
        let used: UInt64
        let available: UInt64
    }

    static func getDiskInfo() -> Info {
        let fileURL = URL(fileURLWithPath: "/")

        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            let used = total > available ? total - available : 0

            return Info(total: total, used: used, available: available)
        } catch {
            return Info(total: 0, used: 0, available: 0)
        }
    }
}
