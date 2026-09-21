//
//  DiagnosticSessionIndex.swift
//  Light Stats
//
//  One entry per app launch inside a report's journal. A report spans several runs
//  (and possibly reboots); the reader should not have to reconstruct that from
//  timestamps and uptime values.
//

import Foundation

nonisolated struct DiagnosticSessionIndex: Sendable, Equatable, Codable {

    struct Session: Sendable, Equatable, Codable {
        let sessionID: String
        let records: Int
        let firstAt: Date?
        let lastAt: Date?
        let launchedAt: Date?
        let terminatedAt: Date?
        let version: String?
        let build: String?
        /// `ProcessInfo.systemUptime` at launch. A value that went *down* between two
        /// sessions means the Mac rebooted — otherwise invisible in a journal.
        let osUptimeAtLaunchSeconds: Double?
    }

    let sessions: [Session]

    static func build(records: [DiagnosticLogService.Record]) -> DiagnosticSessionIndex {
        var order: [String] = []
        var grouped: [String: [DiagnosticLogService.Record]] = [:]
        for record in records {
            if grouped[record.sessionID] == nil {
                order.append(record.sessionID)
            }
            grouped[record.sessionID, default: []].append(record)
        }

        let sessions = order.compactMap { sessionID -> Session? in
            guard let sessionRecords = grouped[sessionID] else { return nil }
            let launch = sessionRecords.first { $0.category == "application" && $0.action == "launched" }
            let terminate = sessionRecords.first { $0.category == "application" && $0.action == "willTerminate" }
            let baseline = sessionRecords.first { $0.category == "environment" && $0.action == "baseline" }
            return Session(
                sessionID: sessionID,
                records: sessionRecords.count,
                firstAt: sessionRecords.map(\.timestamp).min(),
                lastAt: sessionRecords.map(\.timestamp).max(),
                launchedAt: launch?.timestamp,
                terminatedAt: terminate?.timestamp,
                version: launch.flatMap { stringField($0, "version") },
                build: launch.flatMap { stringField($0, "build") },
                osUptimeAtLaunchSeconds: baseline.flatMap { uptimeSeconds($0) }
            )
        }
        return DiagnosticSessionIndex(sessions: sessions.sorted {
            ($0.firstAt ?? .distantPast) < ($1.firstAt ?? .distantPast)
        })
    }

    private static func stringField(_ record: DiagnosticLogService.Record, _ key: String) -> String? {
        guard case .string(let value)? = record.fields[key]?.value else { return nil }
        return value
    }

    /// Reads the launch uptime under its current name, falling back to the name older
    /// builds wrote, so a mixed-version report still yields a comparable series.
    private static func uptimeSeconds(_ record: DiagnosticLogService.Record) -> Double? {
        for key in ["system.uptimeSeconds", "process.uptimeSeconds"] {
            switch record.fields[key]?.value {
            case .double(let value): return value
            case .integer(let value): return Double(value)
            case .unsignedInteger(let value): return Double(value)
            default: continue
            }
        }
        return nil
    }
}
