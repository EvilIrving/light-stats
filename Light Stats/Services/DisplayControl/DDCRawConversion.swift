//
//  DDCRawConversion.swift
//  Light Stats
//

nonisolated enum DDCRawConversion {
    static func rawValue(percent: Double, maximum: UInt16) -> UInt16 {
        let safeMaximum = sanitizedMaximum(maximum)
        let clampedPercent = min(100, max(0, percent))
        return UInt16((clampedPercent / 100 * Double(safeMaximum)).rounded())
    }

    static func percent(rawValue: UInt16, maximum: UInt16) -> Double {
        guard maximum > 0 else { return 0 }
        let clampedRawValue = min(rawValue, maximum)
        return Double(clampedRawValue) / Double(maximum) * 100
    }

    static func sanitizedMaximum(_ maximum: UInt16) -> UInt16 {
        min(max(maximum, 1), 32_767)
    }
}
