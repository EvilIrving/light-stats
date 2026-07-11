//
//  DiagnosticLogService.swift
//  Light Stats
//
//  App-owned structured diagnostics with privacy-aware fields, bounded sample
//  coalescing, a single writer actor, five-day retention, and explicit flush.
//

import Foundation
import os

actor DiagnosticLogService {

    enum Level: String, Codable, Sendable {
        case debug
        case info
        case warning
        case error
    }

    enum Privacy: String, Codable, Sendable {
        case `public`
        case privateLocal
        case secret
    }

    enum Value: Codable, Sendable, Equatable {
        case string(String)
        case integer(Int64)
        case unsignedInteger(UInt64)
        case double(Double)
        case bool(Bool)
        case array([Value])
        case object([String: Value])
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int64.self) {
                self = .integer(value)
            } else if let value = try? container.decode(UInt64.self) {
                self = .unsignedInteger(value)
            } else if let value = try? container.decode(Double.self) {
                self = .double(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([Value].self) {
                self = .array(value)
            } else {
                self = .object(try container.decode([String: Value].self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .integer(let value): try container.encode(value)
            case .unsignedInteger(let value): try container.encode(value)
            case .double(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            case .null: try container.encodeNil()
            }
        }
    }

    struct Field: Codable, Sendable, Equatable {
        let value: Value
        let privacy: Privacy

        static func publicValue(_ value: String) -> Field {
            Field(value: .string(value), privacy: .public)
        }

        static func privateValue(_ value: String) -> Field {
            Field(value: .string(value), privacy: .privateLocal)
        }

        static func privateValue(_ value: Value) -> Field {
            Field(value: value, privacy: .privateLocal)
        }

        static let secret = Field(value: .string("<redacted>"), privacy: .secret)
    }

    struct Record: Codable, Sendable, Equatable {
        let schemaVersion = 2
        let timestamp: Date
        let level: Level
        let category: String
        let action: String
        let fields: [String: Field]
    }

    struct Configuration: Sendable {
        let directory: URL
        let retentionDays: Int
        let maximumBytes: UInt64

        static var production: Configuration {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return Configuration(
                directory: base.appendingPathComponent("Light Stats/Diagnostics", isDirectory: true),
                retentionDays: 5,
                maximumBytes: 1_024 * 1_024 * 1_024
            )
        }
    }

    static let shared = DiagnosticLogService(configuration: .production)
    nonisolated static var diagnosticsDirectoryURL: URL { Configuration.production.directory }

    private static let systemLog = Logger(subsystem: "com.lightstats.app", category: "Diagnostics")
    private static let buffer = DiagnosticRecordBuffer()
    private static let cleanupInterval: TimeInterval = 3600

    private let configuration: Configuration
    private let encoder: JSONEncoder
    private let fileManager: FileManager
    private var currentDay: String?
    private var currentHandle: FileHandle?
    private var lastCleanupAt: Date = .distantPast
    private var isClosed = false

    init(configuration: Configuration, fileManager: FileManager = .default) {
        self.configuration = configuration
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    nonisolated static func record(
        level: Level = .info,
        category: String,
        action: String,
        fields: [String: Field] = [:]
    ) {
        let record = Record(
            timestamp: Date(),
            level: level,
            category: category,
            action: action,
            fields: sanitized(fields)
        )
        guard buffer.enqueue(record, kind: .important) else { return }
        Task { await shared.drain() }
    }

    nonisolated static func recordSample(
        category: String,
        action: String,
        fields: [String: Field] = [:]
    ) {
        let record = Record(
            timestamp: Date(),
            level: .info,
            category: category,
            action: action,
            fields: sanitized(fields)
        )
        guard buffer.enqueue(record, kind: .sample) else { return }
        Task { await shared.drain() }
    }

    nonisolated static func recordPrivate(
        level: Level = .info,
        category: String,
        action: String,
        fields: [String: String] = [:]
    ) {
        record(
            level: level,
            category: category,
            action: action,
            fields: fields.mapValues(Field.privateValue)
        )
    }

    nonisolated static func record(
        level: Level = .info,
        category: String,
        action: String,
        fields: [String: String]
    ) {
        recordPrivate(level: level, category: category, action: action, fields: fields)
    }

    func drain() {
        while let batch = Self.buffer.nextBatch() {
            for record in batch {
                append(record)
            }
        }
    }

    func append(_ record: Record) {
        guard !isClosed else { return }
        do {
            try prepareDirectory()
            try cleanUpIfNeeded(referenceDate: record.timestamp)
            try rotateIfNeeded(for: record.timestamp)
            var data = try encoder.encode(record)
            data.append(0x0A)
            try currentHandle?.write(contentsOf: data)
        } catch {
            Self.systemLog.error("Diagnostic write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func flush() {
        drain()
        do {
            try currentHandle?.synchronize()
        } catch {
            Self.systemLog.error("Diagnostic flush failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func close() {
        guard !isClosed else { return }
        flush()
        try? currentHandle?.close()
        currentHandle = nil
        currentDay = nil
        isClosed = true
    }

    func cleanUp(referenceDate: Date = Date()) throws {
        try prepareDirectory()
        try closeCurrentFile()
        let expiration = referenceDate.addingTimeInterval(-Double(configuration.retentionDays) * 86_400)
        for file in try diagnosticFiles() where file.modifiedAt < expiration {
            try fileManager.removeItem(at: file.url)
        }

        var retained = try diagnosticFiles().sorted { $0.modifiedAt < $1.modifiedAt }
        var totalBytes = retained.reduce(UInt64(0)) { $0 + $1.size }
        while totalBytes > configuration.maximumBytes, let oldest = retained.first {
            try fileManager.removeItem(at: oldest.url)
            totalBytes = totalBytes >= oldest.size ? totalBytes - oldest.size : 0
            retained.removeFirst()
        }
        lastCleanupAt = referenceDate
    }

    private func cleanUpIfNeeded(referenceDate: Date) throws {
        guard referenceDate.timeIntervalSince(lastCleanupAt) >= Self.cleanupInterval else { return }
        try cleanUp(referenceDate: referenceDate)
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: configuration.directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configuration.directory.path)
    }

    private func rotateIfNeeded(for date: Date) throws {
        let day = Self.dayString(date)
        guard currentDay != day || currentHandle == nil else { return }
        try closeCurrentFile()
        let url = configuration.directory.appendingPathComponent("diagnostics-v2-\(day).jsonl")
        if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        currentHandle = handle
        currentDay = day
    }

    private func closeCurrentFile() throws {
        try currentHandle?.synchronize()
        try currentHandle?.close()
        currentHandle = nil
        currentDay = nil
    }

    private func diagnosticFiles() throws -> [DiagnosticFile] {
        let urls = try fileManager.contentsOfDirectory(
            at: configuration.directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix("diagnostics-"), url.pathExtension == "jsonl" else { return nil }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            return DiagnosticFile(
                url: url,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                size: UInt64(max(values.fileSize ?? 0, 0))
            )
        }
    }

    nonisolated static func sanitized(_ fields: [String: Field]) -> [String: Field] {
        fields.mapValues { field in
            guard field.privacy != .secret else { return .secret }
            return Field(value: SensitiveLogFilter.sanitize(field.value), privacy: field.privacy)
        }
    }

    nonisolated private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private struct DiagnosticFile {
        let url: URL
        let modifiedAt: Date
        let size: UInt64
    }
}

nonisolated final class DiagnosticRecordBuffer: @unchecked Sendable {
    private static let batchSize = 128
    private static let maximumSamples = 256
    private static let maximumImportantRecords = 2_048

    enum Kind {
        case important
        case sample
    }

    private let lock = NSLock()
    private var importantRecords: [DiagnosticLogService.Record] = []
    private var samples: [DiagnosticLogService.Record] = []
    private var coalescedSamples: [String: DiagnosticLogService.Record] = [:]
    private var coalescedCount = 0
    private var droppedImportantCount = 0
    private var workerRunning = false

    func enqueue(_ record: DiagnosticLogService.Record, kind: Kind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch kind {
        case .sample:
            if samples.count < Self.maximumSamples {
                samples.append(record)
            } else {
                coalescedSamples[record.category] = record
                coalescedCount += 1
            }
        case .important:
            if importantRecords.count >= Self.maximumImportantRecords {
                importantRecords.removeFirst()
                droppedImportantCount += 1
            }
            importantRecords.append(record)
        }
        guard !workerRunning else { return false }
        workerRunning = true
        return true
    }

    func nextBatch() -> [DiagnosticLogService.Record]? {
        lock.lock()
        defer { lock.unlock() }
        appendBackpressureRecordIfNeeded()
        if importantRecords.isEmpty && samples.isEmpty && !coalescedSamples.isEmpty {
            samples.append(contentsOf: coalescedSamples.values.sorted { $0.category < $1.category })
            coalescedSamples.removeAll()
            importantRecords.append(DiagnosticLogService.Record(
                timestamp: Date(),
                level: .warning,
                category: "logging",
                action: "backpressure",
                fields: [
                    "coalescedSampleCount": .publicValue(String(coalescedCount))
                ]
            ))
            coalescedCount = 0
        }
        guard !importantRecords.isEmpty || !samples.isEmpty else {
            workerRunning = false
            return nil
        }
        var batch = Array(importantRecords.prefix(Self.batchSize))
        importantRecords.removeFirst(batch.count)
        let remaining = Self.batchSize - batch.count
        if remaining > 0 {
            let sampleBatch = Array(samples.prefix(remaining))
            samples.removeFirst(sampleBatch.count)
            batch.append(contentsOf: sampleBatch)
        }
        return batch
    }

    private func appendBackpressureRecordIfNeeded() {
        guard droppedImportantCount > 0 else { return }
        if importantRecords.count >= Self.maximumImportantRecords {
            importantRecords.removeFirst()
            droppedImportantCount += 1
        }
        importantRecords.append(DiagnosticLogService.Record(
            timestamp: Date(),
            level: .warning,
            category: "logging",
            action: "backpressure",
            fields: [
                "droppedImportantCount": .publicValue(String(droppedImportantCount))
            ]
        ))
        droppedImportantCount = 0
    }
}

nonisolated private enum SensitiveLogFilter {
    private static let patterns = [
        "(?i)bearer\\s+[A-Za-z0-9._~+/-]+=*",
        "(?i)\\bsk-[A-Za-z0-9_-]{8,}\\b",
        "(?i)\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b",
        "(?i)(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token)[\\s:=\"']+[^\\s,;]+"
    ]

    static func sanitize(_ value: DiagnosticLogService.Value) -> DiagnosticLogService.Value {
        switch value {
        case .string(let string): return .string(sanitize(string))
        case .array(let values): return .array(values.map(sanitize))
        case .object(let values): return .object(values.mapValues(sanitize))
        case .integer, .unsignedInteger, .double, .bool, .null: return value
        }
    }

    private static func sanitize(_ value: String) -> String {
        var result = value.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "<redacted>",
                options: .regularExpression
            )
        }
        return result
    }
}
