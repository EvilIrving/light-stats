//
//  SMCInfo+Diagnostics.swift
//  Light Stats
//

import Foundation

extension SMCInfo {
    /// Gracefully tear down the persistent SMC connection at app termination.
    static func shutdown() {
        invalidateConnection()
    }

    static func recordProbe(
        operation: String,
        status: DiagnosticLogService.ProbeStatus,
        reasonCode: String,
        fields: [String: DiagnosticLogService.Field] = [:]
    ) {
        DiagnosticLogService.recordProbe(
            component: "SMCInfo",
            operation: operation,
            status: status,
            reasonCode: reasonCode,
            source: "AppleSMC",
            fields: fields
        )
    }

    static func temperatureCandidateFields(_ keys: [String]) -> [String: DiagnosticLogService.Field] {
        ["candidateKeys": .privateValue(.array(keys.map(DiagnosticLogService.Value.string)))]
    }
}
