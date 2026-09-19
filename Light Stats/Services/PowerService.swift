//
//  PowerService.swift
//  Light Stats
//
//  电池/功耗采集：原生 IOKit。
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

    /// AppleSmartBattery 的一层属性表：节点顶层属性，或节点里的一个嵌套 `BatteryData` 字典。
    /// `origin` 只用于诊断标注，说明某个键最终是从哪一层读到的。
    struct BatteryLayer {
        var origin: String
        var values: [String: Any]
    }

    /// 容量/温度键在不同 macOS 版本位于不同层级：
    /// - macOS 26 及更早：`DesignCapacity` / `AppleRawMaxCapacity` / `Temperature` 直接在 AppleSmartBattery 顶层；
    /// - macOS 27 起：顶层只剩 `CycleCount` / `MaxCapacity` / `Voltage` / `InstantAmperage` 等，
    ///   容量移进嵌套的 `BatteryData`（顶层一份精简版），温度与 `PermanentFailureStatus`
    ///   只在子节点（典型为 AppleSmartBatteryPack）的电量计 `BatteryData` 里。
    /// 按层收集后合并，两代系统才能走同一条解析路径。
    private func batteryPropertyLayers(topLevel: [String: Any], service: io_service_t) -> [BatteryLayer] {
        var layers = [BatteryLayer(origin: "AppleSmartBattery", values: topLevel)]
        if let summary = topLevel["BatteryData"] as? [String: Any] {
            layers.append(BatteryLayer(origin: "AppleSmartBattery.BatteryData", values: summary))
        }
        layers.append(contentsOf: Self.childBatteryLayers(of: service))
        return layers
    }

    /// 直接子节点的属性及其 `BatteryData`。无子节点（旧系统、无电池机型）时返回空数组，
    /// 此时读取退化为只认顶层属性，即升级前的行为。
    nonisolated static func childBatteryLayers(of service: io_service_t) -> [BatteryLayer] {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == kIOReturnSuccess else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var layers: [BatteryLayer] = []
        var child = IOIteratorNext(iterator)
        while child != 0 {
            defer { IOObjectRelease(child) }
            if let properties = registryProperties(of: child) {
                let label = registryClassName(of: child)
                layers.append(BatteryLayer(origin: label, values: properties))
                if let nested = properties["BatteryData"] as? [String: Any] {
                    layers.append(BatteryLayer(origin: "\(label).BatteryData", values: nested))
                }
            }
            child = IOIteratorNext(iterator)
        }
        return layers
    }

    /// 按传入顺序从外到内合并：先出现的层优先，同名键不覆盖。
    /// 于是 macOS ≤26 读到的仍是顶层值，macOS 27 由嵌套/子节点补齐。
    nonisolated static func mergedBatteryLayers(_ layers: [BatteryLayer])
        -> (values: [String: Any], origins: [String: String]) {
        var values: [String: Any] = [:]
        var origins: [String: String] = [:]
        for layer in layers {
            for (key, value) in layer.values where values[key] == nil {
                values[key] = value
                origins[key] = layer.origin
            }
        }
        return (values, origins)
    }

    nonisolated static func registryProperties(of entry: io_object_t) -> [String: Any]? {
        var propsRef: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0)
        guard result == kIOReturnSuccess,
              let properties = propsRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return properties
    }

    nonisolated static func registryClassName(of entry: io_object_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(entry, &name) == kIOReturnSuccess else { return "unknown" }
        return String(cString: name)
    }

    private func readSmartBattery() -> SmartData? {
        let source = "IORegistry/AppleSmartBattery"
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            DiagnosticLogService.recordProbe(
                component: "PowerService",
                operation: "readSmartBattery",
                status: .unavailable,
                reasonCode: "serviceNotFound",
                source: source
            )
            return nil
        }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        let propertiesResult = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
        guard propertiesResult == kIOReturnSuccess,
              let dict = propsRef?.takeRetainedValue() as? [String: Any] else {
            DiagnosticLogService.recordProbe(
                component: "PowerService",
                operation: "readSmartBattery",
                status: .failure,
                reasonCode: "propertyReadFailed",
                source: source,
                fields: ["nativeCode": .privateValue(.integer(Int64(propertiesResult)))]
            )
            return nil
        }

        let merged = Self.mergedBatteryLayers(batteryPropertyLayers(topLevel: dict, service: service))
        let properties = merged.values

        var data = SmartData()

        // 循环次数
        data.cycleCount = (properties["CycleCount"] as? NSNumber)?.intValue
        data.healthPercent = Self.healthPercent(from: properties)
        data.conditionOK = Self.conditionOK(from: properties)
        data.temperature = Self.batteryTemperatureCelsius(from: properties)

        // 实时功耗：InstantAmperage(mA, 有符号) × Voltage(mV) → W。
        if let voltage = (properties["Voltage"] as? NSNumber)?.doubleValue,
           let a = signedRegistryInteger(properties["InstantAmperage"] ?? properties["Amperage"]),
           abs(a) <= 30_000 {
            let watts = Double(abs(a)) * voltage / 1_000_000.0
            if watts >= 0, watts < 200 {
                data.powerWatts = watts
            }
        }

        if data.powerWatts == nil,
           let telemetry = properties["PowerTelemetryData"] as? [String: Any],
           let batteryPower = signedRegistryInteger(telemetry["BatteryPower"]) {
            let watts = Double(abs(batteryPower)) / 1_000.0
            if watts >= 0, watts < 200 {
                data.powerWatts = watts
            }
        }

        recordSmartBatteryDiagnostics(properties: properties, origins: merged.origins, data: data)
        return data
    }

    /// 健康度 = 当前最大容量 / 设计容量。
    /// 优先 AppleRawMaxCapacity（电池控制器上报的真实最大容量），
    /// 缺失时回退到 NominalChargeCapacity 或 MaxCapacity（后者在部分机型是百分比，>100 才当容量用）。
    /// system_profiler 用 NominalChargeCapacity，偏乐观（偏高 2-3pp）；这里用真实值。
    nonisolated static func healthPercent(from properties: [String: Any]) -> Int? {
        guard let design = (properties["DesignCapacity"] as? NSNumber)?.doubleValue, design > 0 else {
            return nil
        }
        let rawMax = (properties["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
        let nominal = (properties["NominalChargeCapacity"] as? NSNumber)?.doubleValue
        let maxCap = (properties["MaxCapacity"] as? NSNumber)?.doubleValue
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
        guard let maximum = effectiveMax else { return nil }
        return Swift.min(100, Int((maximum / design * 100).rounded()))
    }

    /// 状态正常与否（best-effort）：PermanentFailureStatus == 0 视为正常。
    nonisolated static func conditionOK(from properties: [String: Any]) -> Bool? {
        guard let status = (properties["PermanentFailureStatus"] as? NSNumber)?.intValue else {
            return nil
        }
        return status == 0
    }

    /// 温度：单位 0.01°C，除以 100。超出合理范围视为脏值丢弃。
    nonisolated static func batteryTemperatureCelsius(from properties: [String: Any]) -> Double? {
        guard let raw = (properties["Temperature"] as? NSNumber)?.doubleValue else { return nil }
        let celsius = raw / 100.0
        return celsius > 0 && celsius < 80 ? celsius : nil
    }

    private func recordSmartBatteryDiagnostics(properties: [String: Any],
                                               origins: [String: String],
                                               data: SmartData) {
        let source = "IORegistry/AppleSmartBattery"
        DiagnosticLogService.recordProbe(
            component: "PowerService",
            operation: "batteryCycleCount",
            status: data.cycleCount == nil ? .unavailable : .success,
            reasonCode: data.cycleCount == nil ? "missingOrInvalidCycleCount" : "valueRead",
            source: source,
            fields: diagnosticFields(for: ["CycleCount"], in: properties, origins: origins)
        )

        let healthKeys = ["DesignCapacity", "AppleRawMaxCapacity", "NominalChargeCapacity", "MaxCapacity"]
        DiagnosticLogService.recordProbe(
            component: "PowerService",
            operation: "batteryHealth",
            status: data.healthPercent == nil ? .unavailable : .success,
            reasonCode: data.healthPercent == nil ? Self.healthFailureReason(properties) : "capacityRatioComputed",
            source: source,
            fields: diagnosticFields(for: healthKeys, in: properties, origins: origins)
        )

        DiagnosticLogService.recordProbe(
            component: "PowerService",
            operation: "batteryTemperature",
            status: data.temperature == nil ? .unavailable : .success,
            reasonCode: Self.batteryTemperatureReason(properties: properties, value: data.temperature),
            source: source,
            fields: diagnosticFields(for: ["Temperature"], in: properties, origins: origins)
        )

        let powerKeys = ["Voltage", "InstantAmperage", "Amperage", "PowerTelemetryData"]
        DiagnosticLogService.recordProbe(
            component: "PowerService",
            operation: "batteryPower",
            status: data.powerWatts == nil ? .unavailable : .success,
            reasonCode: data.powerWatts == nil ? "noUsablePowerSource" : "valueRead",
            source: source,
            fields: diagnosticFields(for: powerKeys, in: properties, origins: origins)
        )
    }

    nonisolated static func healthFailureReason(_ properties: [String: Any]) -> String {
        guard let design = (properties["DesignCapacity"] as? NSNumber)?.doubleValue else {
            return properties["DesignCapacity"] == nil ? "missingDesignCapacity" : "invalidDesignCapacityType"
        }
        guard design > 0 else { return "nonPositiveDesignCapacity" }
        let candidateKeys = ["AppleRawMaxCapacity", "NominalChargeCapacity", "MaxCapacity"]
        let hasNumericCandidate = candidateKeys.contains { properties[$0] is NSNumber }
        return hasNumericCandidate ? "noUsableMaximumCapacity" : "missingOrInvalidMaximumCapacity"
    }

    nonisolated static func batteryTemperatureReason(properties: [String: Any], value: Double?) -> String {
        if value != nil { return "valueRead" }
        guard let raw = properties["Temperature"] else { return "missingTemperature" }
        guard let number = raw as? NSNumber else { return "invalidTemperatureType" }
        let celsius = number.doubleValue / 100
        return celsius > 0 && celsius < 80 ? "parseFailed" : "temperatureOutOfRange"
    }

    private func diagnosticFields(for keys: [String],
                                  in properties: [String: Any],
                                  origins: [String: String])
        -> [String: DiagnosticLogService.Field] {
        let attempts = keys.map { key -> DiagnosticLogService.Value in
            guard let value = properties[key] else {
                return .object([
                    "key": .string(key),
                    "present": .bool(false)
                ])
            }
            var detail: [String: DiagnosticLogService.Value] = [
                "key": .string(key),
                "present": .bool(true),
                "type": .string(String(describing: type(of: value))),
                "origin": .string(origins[key] ?? "unknown")
            ]
            if let number = value as? NSNumber {
                detail["numericValue"] = .double(number.doubleValue)
            } else if let dictionary = value as? [String: Any] {
                detail["nestedKeys"] = .array(dictionary.keys.sorted().map(DiagnosticLogService.Value.string))
            }
            return .object(detail)
        }
        return ["attempts": .privateValue(.array(attempts))]
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
