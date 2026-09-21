//
//  DiagnosticJournalSummary.swift
//  Light Stats
//
//  A support report is a folder of raw JSONL. This is the part that answers
//  "what is in here?" without the reader writing a parser: coverage, counts,
//  and probe reason codes.
//

import Foundation

/// Counts and coverage of the journal lines that were copied into a report.
nonisolated struct DiagnosticJournalSummary: Sendable, Equatable, Codable {

    /// One journal file as it appears in the report.
    struct FileSummary: Sendable, Equatable, Codable {
        let name: String
        /// Bytes actually written into the report.
        let bytes: Int
        let records: Int
        /// Lines the export filter kept out of the report on purpose.
        let excludedRecords: Int
        /// Lines that could not be parsed (truncated write, newer schema).
        let unparsableRows: Int
        let firstAt: Date?
        let lastAt: Date?
    }

    /// One source journal file, already filtered, ready to summarize.
    struct FileInput: Sendable, Equatable {
        let name: String
        let bytes: Int
        let copiedLines: [String]
        let excludedRecords: Int
    }

    let files: [FileSummary]
    let totalRecords: Int
    let excludedRecords: Int
    let unparsableRows: Int
    let firstAt: Date?
    let lastAt: Date?
    /// `info` → count.
    let levels: [String: Int]
    /// `system` → count.
    let categories: [String: Int]
    /// `windowManagement/gestureRejected` → count.
    let actions: [String: Int]
    /// `fanSpeed|noFanKeys` → count: a report can be read for reasons at a glance.
    let probeReasons: [String: Int]

    /// Decodes the JSONL once and returns both report metadata products.
    /// Unparsable rows are counted per file, never dropped silently.
    static func build(files: [FileInput]) -> (summary: DiagnosticJournalSummary, sessions: DiagnosticSessionIndex) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var summaries: [FileSummary] = []
        var records: [DiagnosticLogService.Record] = []
        var unparsableByFile: [String: Int] = [:]

        for file in files {
            var fileRecords: [DiagnosticLogService.Record] = []
            var unparsable = 0
            for line in file.copiedLines {
                guard let data = line.data(using: .utf8),
                      let record = try? decoder.decode(DiagnosticLogService.Record.self, from: data) else {
                    unparsable += 1
                    continue
                }
                fileRecords.append(record)
            }
            records.append(contentsOf: fileRecords)
            unparsableByFile[file.name] = unparsable
            summaries.append(FileSummary(
                name: file.name,
                bytes: file.bytes,
                records: fileRecords.count,
                excludedRecords: file.excludedRecords,
                unparsableRows: unparsable,
                firstAt: fileRecords.map(\.timestamp).min(),
                lastAt: fileRecords.map(\.timestamp).max()
            ))
        }

        let summary = DiagnosticJournalSummary(
            files: summaries,
            totalRecords: records.count,
            excludedRecords: summaries.reduce(0) { $0 + $1.excludedRecords },
            unparsableRows: summaries.reduce(0) { $0 + $1.unparsableRows },
            firstAt: records.map(\.timestamp).min(),
            lastAt: records.map(\.timestamp).max(),
            levels: counts(records.map(\.level.rawValue)),
            categories: counts(records.map(\.category)),
            actions: counts(records.map { "\($0.category)/\($0.action)" }),
            probeReasons: counts(records.compactMap { record in
                guard record.category == "probe",
                      let reason = stringField(record, "reasonCode") else { return nil }
                return "\(record.action)|\(reason)"
            })
        )
        return (summary, DiagnosticSessionIndex.build(records: records))
    }

    private static func stringField(_ record: DiagnosticLogService.Record, _ key: String) -> String? {
        guard case .string(let value)? = record.fields[key]?.value else { return nil }
        return value
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for value in values {
            result[value, default: 0] += 1
        }
        return result
    }
}
