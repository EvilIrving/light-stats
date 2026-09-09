//
//  GPUInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation
import IOKit

enum GPUInfo {

    static func getGPUUsage() -> Double? {
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
                reasonCode: "serviceEnumerationFailed",
                source: source,
                fields: ["nativeCode": .privateValue(.integer(Int64(result)))]
            )
            return nil
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
                        reasonCode: "valueRead",
                        source: source,
                        fields: ["selectedKey": .privateValue(key)]
                    )
                    return utilization
                }
            }

            entry = IOIteratorNext(iterator)
        }

        let reason: String
        if acceleratorCount == 0 {
            reason = "noAcceleratorServices"
        } else if statisticsCount == 0 {
            reason = "missingPerformanceStatistics"
        } else {
            reason = "noSupportedUtilizationKey"
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
        return nil
    }
}
