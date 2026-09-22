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
        formatSpeed(bytesPerSecond, significantDigits: nil)
    }

    /// Status-bar network speeds: keep three significant digits so up/down stay visually aligned
    /// as the magnitude crosses unit boundaries (B/s → KB/s → MB/s).
    static func formatSpeedAligned(_ bytesPerSecond: Double) -> String {
        formatSpeed(bytesPerSecond, significantDigits: 3)
    }

    private static func formatSpeed(_ bytesPerSecond: Double, significantDigits: Int?) -> String {
        let magnitude = max(bytesPerSecond, 0)
        let (value, unit): (Double, String)
        if magnitude >= 1_000_000 {
            value = magnitude / 1_000_000
            unit = "MB/s"
        } else if magnitude >= 1_000 {
            value = magnitude / 1_000
            unit = "KB/s"
        } else {
            value = magnitude
            unit = "B/s"
        }
        guard let significantDigits else {
            if unit == "MB/s" {
                return String(format: "%.1f %@", value, unit)
            }
            return String(format: "%.0f %@", value, unit)
        }
        return "\(formatSignificant(value, digits: significantDigits)) \(unit)"
    }

    /// Format a positive magnitude with a fixed significant-digit budget.
    static func formatSignificant(_ value: Double, digits: Int) -> String {
        let clamped = max(value, 0)
        guard clamped > 0 else { return digits >= 3 ? "0.00" : "0" }
        let digits = max(digits, 1)
        let exponent = floor(log10(clamped))
        let decimals = max(0, digits - Int(exponent) - 1)
        let factor = pow(10.0, Double(decimals))
        let rounded = (clamped * factor).rounded() / factor
        return String(format: "%.\(decimals)f", rounded)
    }
}
