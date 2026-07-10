//
//  PowerService.swift
//  Light Stats
//
//  电池/功耗采集：原生 IOKit，零外发。
//  - 电量/状态/剩余时间：IOPowerSources（IOPSCopyPowerSourcesInfo），每周期读，便宜。
//  - 循环/健康/功耗/温度：AppleSmartBattery（IORegistry），慢变量，缓存 30s。
//
//  actor 隔离：IOKit 读取在 actor 自身 executor（非主线程）执行；结果回 @MainActor 绑定视图。
//

import Foundation
import IOKit
import IOKit.ps

actor PowerService {

    /// AppleSmartBattery 派生的慢变量 + 温度/功耗，缓存 30s（避免每秒读 IORegistry）。
    private struct SmartData {
        var cycleCount: Int?
        var healthPercent: Int?
        var conditionOK: Bool?
        var powerWatts: Double?
        var temperature: Double?
    }

    private var cachedSmart: SmartData?
    private var cachedSmartAt: Date?

    /// 采集当前电池信息。无电池 → `.noBattery`。
    func current() -> BatteryInfo {
        guard let live = readPowerSources() else {
            return .noBattery
        }
        let smart = smartData()
        return BatteryInfo(
            state: live.state,
            percent: live.percent,
            timeRemaining: live.timeRemaining,
            cycleCount: smart.cycleCount,
            healthPercent: smart.healthPercent,
            conditionOK: smart.conditionOK,
            powerWatts: smart.powerWatts,
            temperature: smart.temperature
        )
    }

    // MARK: - IOPowerSources（电量/状态/剩余时间）

    private struct LivePower {
        var state: BatteryInfo.State
        var percent: Double
        var timeRemaining: Int?
    }

    /// 读 IOPowerSources。无任何电源（台式机/无电池）→ nil。
    private func readPowerSources() -> LivePower? {
        guard let snapshotRef = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourcesRef = IOPSCopyPowerSourcesList(snapshotRef)?.takeRetainedValue() as? [CFTypeRef],
              !sourcesRef.isEmpty else {
            return nil
        }

        // 找第一个内置电池电源。
        for source in sourcesRef {
            guard let desc = IOPSGetPowerSourceDescription(snapshotRef, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }

            // 仅认电池类型电源（排除 UPS 等）。
            if let type = desc[kIOPSTypeKey] as? String, type != kIOPSInternalBatteryType {
                continue
            }

            let current = (desc[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let max = (desc[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
            let percent = max > 0 ? min(100, current / max * 100) : 0

            let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            let isCharged = (desc[kIOPSIsChargedKey] as? Bool) ?? false
            // 是否已接外部电源：电量保护（停在 80%）时 IsCharging 为 false，但仍在用市电，
            // 不能算「使用电池」。靠电源状态而非 IsCharging 判定。
            let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            let state: BatteryInfo.State
            if isCharged {
                state = .charged
            } else if isCharging {
                state = .charging
            } else if onAC {
                state = .acNotCharging
            } else {
                state = .discharging
            }

            // 充电时看充满时间，放电时看剩余时间；-1 表示计算中/未知。
            let rawTimeKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let rawTime = (desc[rawTimeKey] as? NSNumber)?.intValue
            let timeRemaining: Int? = (rawTime ?? -1) >= 0 ? rawTime : nil

            return LivePower(state: state, percent: percent, timeRemaining: timeRemaining)
        }

        return nil
    }

    // MARK: - AppleSmartBattery（循环/健康/功耗/温度，缓存 30s）

    private func smartData() -> SmartData {
        if let cachedSmart, let at = cachedSmartAt,
           Date().timeIntervalSince(at) < AppConfig.batteryHealthCacheTTL {
            return cachedSmart
        }
        let data = readSmartBattery() ?? SmartData()
        cachedSmart = data
        cachedSmartAt = Date()
        return data
    }

    private func readSmartBattery() -> SmartData? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = propsRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        var data = SmartData()

        // 循环次数
        data.cycleCount = (dict["CycleCount"] as? NSNumber)?.intValue

        // 健康度 = 当前最大容量 / 设计容量。
        // 优先 AppleRawMaxCapacity（电池控制器上报的真实最大容量），
        // 缺失时回退到 NominalChargeCapacity 或 MaxCapacity（Intel，mAh）。
        // system_profiler 用 NominalChargeCapacity，偏乐观（偏高 2-3pp）；这里用真实值。
        if let design = (dict["DesignCapacity"] as? NSNumber)?.doubleValue, design > 0 {
            let rawMax = (dict["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
            let nominal = (dict["NominalChargeCapacity"] as? NSNumber)?.doubleValue
            let maxCap = (dict["MaxCapacity"] as? NSNumber)?.doubleValue
            let effectiveMax: Double?
            if let rawMax, rawMax > 0 {
                effectiveMax = rawMax
            } else if let nominal, nominal > 0 {
                effectiveMax = nominal
            } else if let maxCap, maxCap > 0, maxCap > 100 {
                // MaxCapacity ≤100 时是百分比（充满上限/电量），不是 mAh 容量，跳过。
                effectiveMax = maxCap
            } else {
                effectiveMax = nil
            }
            if let m = effectiveMax {
                data.healthPercent = Swift.min(100, Int((m / design * 100).rounded()))
            }
        }

        // 状态正常与否（best-effort）：PermanentFailureStatus == 0 视为正常。
        if let pfs = (dict["PermanentFailureStatus"] as? NSNumber)?.intValue {
            data.conditionOK = (pfs == 0)
        }

        // 温度：单位 0.01°C，除以 100。超出合理范围视为脏值丢弃。
        if let t = (dict["Temperature"] as? NSNumber)?.doubleValue {
            let celsius = t / 100.0
            if celsius > 0, celsius < 80 {
                data.temperature = celsius
            }
        }

        // 实时功耗：InstantAmperage(mA, 有符号) × Voltage(mV) → W。
        if let voltage = (dict["Voltage"] as? NSNumber)?.doubleValue,
           let a = signedRegistryInteger(dict["InstantAmperage"] ?? dict["Amperage"]),
           abs(a) <= 30_000 {
            let watts = Double(abs(a)) * voltage / 1_000_000.0
            if watts >= 0, watts < 200 {
                data.powerWatts = watts
            }
        }

        if data.powerWatts == nil,
           let telemetry = dict["PowerTelemetryData"] as? [String: Any],
           let batteryPower = signedRegistryInteger(telemetry["BatteryPower"]) {
            let watts = Double(abs(batteryPower)) / 1_000.0
            if watts >= 0, watts < 200 {
                data.powerWatts = watts
            }
        }

        return data
    }

    /// IORegistry 可能把负电流/功耗作为 UInt64 two's complement 暴露，这里还原成真实有符号值。
    private func signedRegistryInteger(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber else { return nil }
        let signed = number.int64Value
        if signed < 0 {
            return signed
        }
        let unsigned = number.uint64Value
        if unsigned > UInt64(Int64.max) {
            return Int64(bitPattern: unsigned)
        }
        return signed
    }
}
