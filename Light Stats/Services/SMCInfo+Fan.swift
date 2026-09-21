//
//  SMCInfo+Fan.swift
//  Light Stats
//
//  风扇探测。与温度探测分开一个文件：这里多了「为什么没有值」的取证，体积也大。
//  关键区别是 `noFanKeys`（机器没有风扇）与 `fanKeysUnreadable`（键在但读不出）：
//  前者是 MacBook Air 的正常结果，后者是回归信号。
//

import Foundation

extension SMCInfo {

    // MARK: - Fan probe

    /// 风扇探测的原因码。支持报告靠它们区分「机器没有风扇」和「有风扇但读不到」。
    enum FanReason {
        static let valueRead = "valueRead"
        static let fallbackIndexRead = "fallbackIndexRead"
        static let valueReadAfterReconnect = "valueReadAfterReconnect"
        /// SMC 里没有风扇键：无风扇机型（MacBook Air）的正常结果。
        static let noFanKeys = "noFanKeys"
        /// 风扇键存在但读不出有效值：键位/格式回归的信号。
        static let fanKeysUnreadable = "fanKeysUnreadable"
        static let connectionUnavailable = "connectionUnavailable"
        static let reconnectFailed = "reconnectFailed"
    }

    struct FanKeyProbe: Sendable, Equatable {
        let key: String
        let outcome: KeyReadOutcome
        /// 转速键 → RPM；`FNum` → 风扇数量。读不出有效值时 nil。
        let value: Int?
    }

    struct FanProbe: Sendable, Equatable {
        let rpm: Int?
        let reasonCode: String
        let fanCountFromSMC: Int?
        let keys: [FanKeyProbe]

        /// 报告在 `probeCollectionEnabled == false` 时使用的占位：没有采集过，不等于没有风扇。
        static let notCollected = FanProbe(
            rpm: nil,
            reasonCode: "notCollected",
            fanCountFromSMC: nil,
            keys: []
        )
    }

    static func getFanSpeed() -> Int? {
        getFanProbe().rpm
    }

    /// 风扇探测：值 + 「为什么没有值」。调用方要读数时用 `getFanSpeed()`；
    /// 支持报告要解释原因时用本方法。
    static func getFanProbe() -> FanProbe {
        guard ensureConnection() else {
            let probe = FanProbe(
                rpm: nil,
                reasonCode: FanReason.connectionUnavailable,
                fanCountFromSMC: nil,
                keys: []
            )
            Self.recordProbe(
                operation: "fanSpeed",
                status: .unavailable,
                reasonCode: FanReason.connectionUnavailable,
                fields: fanEvidenceFields(probe, reconnected: false)
            )
            return probe
        }

        let first = readFanPass()
        if let rpm = first.bestRPM {
            let reason = first.usedFallbackIndex ? FanReason.fallbackIndexRead : FanReason.valueRead
            let probe = FanProbe(
                rpm: rpm,
                reasonCode: reason,
                fanCountFromSMC: first.fanCount,
                keys: first.probes
            )
            Self.recordProbe(
                operation: "fanSpeed",
                status: .success,
                reasonCode: reason,
                fields: fanEvidenceFields(probe, reconnected: false)
            )
            return probe
        }

        // Possible stale connection (e.g. after sleep); reconnect and retry once.
        invalidateConnection()
        guard ensureConnection() else {
            let probe = FanProbe(
                rpm: nil,
                reasonCode: FanReason.reconnectFailed,
                fanCountFromSMC: first.fanCount,
                keys: first.probes
            )
            Self.recordProbe(
                operation: "fanSpeed",
                status: .unavailable,
                reasonCode: FanReason.reconnectFailed,
                fields: fanEvidenceFields(probe, reconnected: true)
            )
            return probe
        }

        let retry = readFanPass()
        let reason: String
        if retry.bestRPM != nil {
            reason = retry.usedFallbackIndex ? FanReason.fallbackIndexRead : FanReason.valueReadAfterReconnect
        } else {
            reason = Self.fanFailureReason(anyFanKeyPresent: first.hasFanKey || retry.hasFanKey)
        }
        let probe = FanProbe(
            rpm: retry.bestRPM,
            reasonCode: reason,
            fanCountFromSMC: retry.fanCount ?? first.fanCount,
            keys: retry.probes.isEmpty ? first.probes : retry.probes
        )
        Self.recordProbe(
            operation: "fanSpeed",
            status: probe.rpm == nil ? .unavailable : .success,
            reasonCode: reason,
            fields: fanEvidenceFields(probe, reconnected: true)
        )
        return probe
    }

    /// 「没有转速」的两种成因：机器没有风扇硬件，还是键在但读不出（回归信号）。
    nonisolated static func fanFailureReason(anyFanKeyPresent: Bool) -> String {
        anyFanKeyPresent ? FanReason.fanKeysUnreadable : FanReason.noFanKeys
    }

    /// 探测证据：`FNum` 与每个转速键各自是否存在、读到了什么。
    nonisolated static func fanEvidenceValues(_ probe: FanProbe) -> [DiagnosticLogService.Value] {
        probe.keys.map { key -> DiagnosticLogService.Value in
            var object: [String: DiagnosticLogService.Value] = [
                "key": .string(key.key),
                "present": .bool(key.outcome != .missing),
                "outcome": .string(key.outcome.rawValue)
            ]
            if let value = key.value {
                object["value"] = .integer(Int64(value))
            }
            return .object(object)
        }
    }

    nonisolated static func fanEvidenceFields(
        _ probe: FanProbe,
        reconnected: Bool
    ) -> [String: DiagnosticLogService.Field] {
        var fields: [String: DiagnosticLogService.Field] = [
            "attempts": .privateValue(.array(fanEvidenceValues(probe))),
            "reconnected": .publicValue(reconnected ? "true" : "false")
        ]
        fields["fanCount"] = .privateValue(
            probe.fanCountFromSMC.map { .integer(Int64($0)) } ?? .null
        )
        return fields
    }

    /// 一轮风扇读键：先按 `FNum` 声明的数量读，读不到再退化为索引 0–3。
    private struct FanReadPass {
        var fanCount: Int?
        var maxDeclaredRPM: Int?
        var fallbackRPM: Int?
        var probes: [FanKeyProbe] = []

        var bestRPM: Int? { maxDeclaredRPM ?? fallbackRPM }
        var usedFallbackIndex: Bool { maxDeclaredRPM == nil && fallbackRPM != nil }
        /// 至少有一个风扇键存在（无论值是否可读）——据此区分「无风扇」和「读不出」。
        var hasFanKey: Bool { probes.contains { $0.outcome != .missing } }
    }

    private static func readFanPass() -> FanReadPass {
        var pass = FanReadPass()
        let countResult = readKeyProbe("FNum")
        let declaredCount = countResult.bytes?.first.map { Int($0) }
        pass.fanCount = declaredCount
        pass.probes.append(FanKeyProbe(key: "FNum", outcome: countResult.outcome, value: declaredCount))

        let effectiveCount = max(declaredCount ?? 1, 1)
        for index in 0..<min(effectiveCount, 4) {
            let probe = readFanKey(index: index)
            pass.probes.append(probe)
            if let rpm = probe.value {
                pass.maxDeclaredRPM = max(pass.maxDeclaredRPM ?? rpm, rpm)
            }
        }

        if pass.maxDeclaredRPM == nil {
            for index in 0..<4 {
                let probe = readFanKey(index: index)
                if !pass.probes.contains(where: { $0.key == probe.key }) {
                    pass.probes.append(probe)
                }
                if let rpm = probe.value, pass.fallbackRPM == nil {
                    pass.fallbackRPM = rpm
                }
            }
        }
        return pass
    }

    /// 读一个风扇转速键：区分「键不存在」「键在但读失败」「读到但解析不出 RPM」。
    private static func readFanKey(index: Int) -> FanKeyProbe {
        let key = String(format: "F%dAc", index)
        let result = readKeyProbe(key)
        guard let bytes = result.bytes else {
            return FanKeyProbe(key: key, outcome: result.outcome, value: nil)
        }
        return FanKeyProbe(key: key, outcome: .value, value: parseFanRPM(from: bytes))
    }

    /// 风扇转速键的字节 → RPM。
    /// M2/M3/M4 用 `flt`（4 字节小端浮点），旧机型用 FPE2（2 字节）。4 字节的数据就是 float：
    /// 超出 0–10000 说明它不是转速，不能再用 FPE2 去凑一个数出来（那会凭空造出一个假转速）。
    nonisolated static func parseFanRPM(from data: [UInt8]) -> Int? {
        if data.count >= 4 {
            let floatValue = data.withUnsafeBytes { ptr -> Float in
                ptr.load(as: Float.self)
            }
            // Allow 0 RPM (fan stopped) - valid range 0-10000
            guard floatValue >= 0 && floatValue < 10000 else { return nil }
            return Int(floatValue)
        }

        guard data.count >= 2 else { return nil }
        let byte0 = Int(data[0])
        let byte1 = Int(data[1])

        // FPE2 format: unsigned fixed-point with 2 fractional bits
        // Variant 1: (byte0 << 6) | (byte1 >> 2)
        let fpe2Variant1 = (byte0 << 6) | (byte1 >> 2)
        if fpe2Variant1 >= 0 && fpe2Variant1 < 10000 {
            return fpe2Variant1
        }

        // Variant 2: (rawValue >> 2)
        let rawValue = (byte0 << 8) | byte1
        let fpe2Variant2 = rawValue >> 2
        if fpe2Variant2 >= 0 && fpe2Variant2 < 10000 {
            return fpe2Variant2
        }

        return nil
    }

}
