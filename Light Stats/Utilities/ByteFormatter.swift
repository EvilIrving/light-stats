//
//  ByteFormatter.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation

enum ByteFormatter {

    static func format(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory  // 改为 .memory 使用二进制 (1 GB = 1024³ bytes)
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// 磁盘空间格式化，保留一位小数。
    /// 不用 ceil：ceil 会把 81.09 GB 夸大成 82 GB（高估可用空间），改用一位小数四舍五入 → 81.1。
    static func formatDisk(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(bytes) / 1_000_000
            return String(format: "%.0f MB", mb)
        }
    }

    static func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }
}
