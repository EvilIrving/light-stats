//
//  GPUInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation
import IOKit

enum GPUInfo {

    /// GPU 探测的原因码（写进诊断日志，支持报告据此解释「为什么没有 GPU 读数」）。
    enum GPUReason {
        static let valueRead = "valueRead"
        static let serviceEnumerationFailed = "serviceEnumerationFailed"
        static let noAcceleratorServices = "noAcceleratorServices"
        static let missingPerformanceStatistics = "missingPerformanceStatistics"
        static let noSupportedUtilizationKey = "noSupportedUtilizationKey"
    }

    struct GPUProbe: Sendable, Equatable {
        let usage: Double?
        let reasonCode: String
        let selectedKey: String?

        /// 报告在 `probeCollectionEnabled == false` 时使用的占位：没有采集过，不等于没有 GPU。
        static let notCollected = GPUProbe(usage: nil, reasonCode: "notCollected", selectedKey: nil)
    }

    static func getGPUUsage() -> Double? {
        getGPUUsageProbe().usage
    }

    /// GPU 探测：值 + 「为什么没有值」。调用方要读数时用 `getGPUUsage()`；
    /// 支持报告要解释原因时用本方法。
    static func getGPUUsageProbe() -> GPUProbe {
        let source = "IORegistry/IOAccelerator/PerformanceStatistics"
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        )

        guard result == KERN_SUCCESS else {
            DiagnosticLogService.recordProbe(
                component: "GPUInfo",
                operation: "gpuUtilization",
                status: .failure,
                reasonCode: GPUReason.serviceEnumerationFailed,
                source: source,
                fields: ["nativeCode": .privateValue(.integer(Int64(result)))]
            )
            return GPUProbe(
                usage: nil,
                reasonCode: GPUReason.serviceEnumerationFailed,
                selectedKey: nil
            )
        }
        defer { IOObjectRelease(iterator) }

        let candidateKeys = ["Device Utilization %", "GPU Activity(%)", "GPU Core Utilization"]
        var acceleratorCount = 0
        var statisticsCount = 0
        var observedKeys = Set<String>()
        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry) }
            acceleratorCount += 1

            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = properties?.takeRetainedValue() as? [String: Any],
               let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                statisticsCount += 1
                observedKeys.formUnion(perfStats.keys)
                for key in candidateKeys {
                    guard let utilization = (perfStats[key] as? NSNumber)?.doubleValue else { continue }
                    DiagnosticLogService.recordProbe(
                        component: "GPUInfo",
                        operation: "gpuUtilization",
                        status: .success,
                        reasonCode: GPUReason.valueRead,
                        source: source,
                        fields: ["selectedKey": .privateValue(key)]
                    )
                    return GPUProbe(usage: utilization, reasonCode: GPUReason.valueRead, selectedKey: key)
                }
            }

            entry = IOIteratorNext(iterator)
        }

        let reason: String
        if acceleratorCount == 0 {
            reason = GPUReason.noAcceleratorServices
        } else if statisticsCount == 0 {
            reason = GPUReason.missingPerformanceStatistics
        } else {
            reason = GPUReason.noSupportedUtilizationKey
        }
        DiagnosticLogService.recordProbe(
            component: "GPUInfo",
            operation: "gpuUtilization",
            status: .unavailable,
            reasonCode: reason,
            source: source,
            fields: [
                "acceleratorCount": .privateValue(.integer(Int64(acceleratorCount))),
                "statisticsCount": .privateValue(.integer(Int64(statisticsCount))),
                "candidateKeys": .privateValue(.array(candidateKeys.map(DiagnosticLogService.Value.string))),
                "observedKeys": .privateValue(.array(observedKeys.sorted().map(DiagnosticLogService.Value.string)))
            ]
        )
        return GPUProbe(usage: nil, reasonCode: reason, selectedKey: nil)
    }
}
