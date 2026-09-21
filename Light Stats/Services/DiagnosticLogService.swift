//
//  DiagnosticLogService.swift
//  Light Stats
//
//  App-owned structured diagnostics with privacy-aware fields, semantic
//  rate control, a single writer actor, bounded retention, and explicit flush.
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
        let schemaVersion: Int
        let eventVersion: Int
        let sessionID: String
        let timestamp: Date
        let level: Level
        let category: String
        let action: String
        let fields: [String: Field]

        init(
            timestamp: Date,
            level: Level,
            category: String,
            action: String,
            fields: [String: Field],
            eventVersion: Int = 1,
            sessionID: String = DiagnosticLogService.sessionID
        ) {
            schemaVersion = 3
            self.eventVersion = eventVersion
            self.sessionID = sessionID
            self.timestamp = timestamp
            self.level = level
            self.category = category
            self.action = action
            self.fields = fields
        }
    }

    enum ProbeStatus: String, Codable, Sendable {
        case success
        case degraded
        case unavailable
        case unsupported
        case failure
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
                retentionDays: 7,
                maximumBytes: 50 * 1_024 * 1_024
            )
        }
    }

    static let shared = DiagnosticLogService(configuration: .production)
    nonisolated static let sessionID = UUID().uuidString
    nonisolated static var diagnosticsDirectoryURL: URL { Configuration.production.directory }

    /// Retention/rate policy as reported to the user: a support package must be able to
    /// explain why it does not contain an earlier day, or why a sample is missing.
    nonisolated static func journalPolicyDescription() -> [String: Int] {
        [
            "retentionDays": Configuration.production.retentionDays,
            "maximumBytes": Int(clamping: Configuration.production.maximumBytes),
            "sampleIntervalSeconds": Int(defaultSampleInterval),
            "stateHeartbeatSeconds": Int(defaultStateHeartbeatInterval)
        ]
    }

    /// Default spacing for continuously changing metric samples.
    nonisolated static let defaultSampleInterval: TimeInterval = 45
    /// How often an unchanged state is re-recorded while it persists.
    nonisolated static let defaultStateHeartbeatInterval: TimeInterval = 6 * 60 * 60

    private static let systemLog = Logger(subsystem: AppLogger.subsystem, category: "Diagnostics")
    private static let buffer = DiagnosticRecordBuffer()
    private static let policy = DiagnosticJournalPolicy(
        sampleInterval: defaultSampleInterval,
        stateHeartbeatInterval: defaultStateHeartbeatInterval
    )
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

    /// Test seam: reset sample, state-change, and heartbeat throttle state.
    nonisolated static func resetPolicyForTesting(
        sampleInterval: TimeInterval = defaultSampleInterval,
        stateHeartbeatInterval: TimeInterval = defaultStateHeartbeatInterval
    ) {
        policy.reset(sampleInterval: sampleInterval, stateHeartbeatInterval: stateHeartbeatInterval)
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
        let cleaned = sanitized(fields)
        guard policy.allowsSample(category: category, action: action, at: Date()) else { return }
        let record = Record(
            timestamp: Date(),
            level: .info,
            category: category,
            action: action,
            fields: cleaned
        )
        guard buffer.enqueue(record, kind: .sample) else { return }
        Task { await shared.drain() }
    }

    /// Writes the first observed state, every state change, and a sparse heartbeat while unchanged.
    nonisolated static func recordState(
        level: Level = .info,
        category: String,
        action: String,
        identity: String = "default",
        fingerprint: String? = nil,
        fields: [String: Field] = [:]
    ) {
        let cleaned = sanitized(fields)
        guard policy.allowsState(
            category: category,
            action: action,
            identity: identity,
            fingerprint: fingerprint ?? canonicalString(cleaned),
            at: Date()
        ) else { return }
        record(level: level, category: category, action: action, fields: cleaned)
    }

    /// Standard collector diagnostic. Missing data is explicit instead of collapsing into nil.
    nonisolated static func recordProbe(
        component: String,
        operation: String,
        identity: String? = nil,
        status: ProbeStatus,
        reasonCode: String,
        source: String,
        fields: [String: Field] = [:]
    ) {
        var payload = fields
        payload["component"] = .publicValue(component)
        payload["status"] = .publicValue(status.rawValue)
        payload["reasonCode"] = .publicValue(reasonCode)
        payload["source"] = .publicValue(source)
        let level: Level = switch status {
        case .success: .info
        case .degraded, .unavailable, .unsupported: .warning
        case .failure: .error
        }
        recordState(
            level: level,
            category: "probe",
            action: operation,
            identity: identity ?? component,
            fingerprint: "\(status.rawValue)|\(reasonCode)|\(source)",
            fields: payload
        )
    }

    /// Repeated human-readable messages are useful, but identical copies are not.
    nonisolated static func recordRepeatedMessage(
        level: Level,
        category: String,
        message: String
    ) {
        recordState(
            level: level,
            category: category,
            action: "message",
            identity: message,
            fields: ["message": .privateValue(message)]
        )
    }

    /// High-frequency events of one kind are useful as a rate, not as a stream.
    /// The first occurrence writes immediately; afterwards at most one record per
    /// `interval` per identity, carrying how many identical occurrences it swallowed.
    /// No occurrence is ever severity-filtered — only duplicates are folded.
    nonisolated static func recordThrottled(
        level: Level = .info,
        category: String,
        action: String,
        identity: String,
        interval: TimeInterval,
        fields: [String: Field] = [:]
    ) {
        let cleaned = sanitized(fields)
        guard let suppressed = policy.throttledCount(
            category: category,
            action: action,
            identity: identity,
            interval: interval,
            at: Date()
        ) else { return }
        record(level: level, category: category, action: action, fields: throttledFields(cleaned, suppressed: suppressed))
    }

    /// Payload of a throttled record: the original fields plus how many identical
    /// occurrences were folded into this one.
    nonisolated static func throttledFields(
        _ fields: [String: Field],
        suppressed: Int
    ) -> [String: Field] {
        var payload = fields
        payload["suppressedCount"] = .publicValue(String(suppressed))
        return payload
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
        var filesRemovedByAge = 0
        var bytesRemovedByAge: UInt64 = 0
        for file in try diagnosticFiles() where file.modifiedAt < expiration {
            try fileManager.removeItem(at: file.url)
            filesRemovedByAge += 1
            bytesRemovedByAge += file.size
        }

        var retained = try diagnosticFiles().sorted { $0.modifiedAt < $1.modifiedAt }
        var totalBytes = retained.reduce(UInt64(0)) { $0 + $1.size }
        var filesRemovedBySize = 0
        var bytesRemovedBySize: UInt64 = 0
        while totalBytes > configuration.maximumBytes, let oldest = retained.first {
            try fileManager.removeItem(at: oldest.url)
            totalBytes = totalBytes >= oldest.size ? totalBytes - oldest.size : 0
            filesRemovedBySize += 1
            bytesRemovedBySize += oldest.size
            retained.removeFirst()
        }
        lastCleanupAt = referenceDate

        // A support report missing earlier days must be able to tell "retention deleted it"
        // apart from "the app was not running".
        guard filesRemovedByAge > 0 || filesRemovedBySize > 0 else { return }
        Self.record(
            category: "diagnostics",
            action: "cleaned",
            fields: [
                "retentionDays": .privateValue(.integer(Int64(configuration.retentionDays))),
                "maximumBytes": .privateValue(.unsignedInteger(configuration.maximumBytes)),
                "filesRemovedByAge": .privateValue(.integer(Int64(filesRemovedByAge))),
                "bytesRemovedByAge": .privateValue(.unsignedInteger(bytesRemovedByAge)),
                "filesRemovedBySize": .privateValue(.integer(Int64(filesRemovedBySize))),
                "bytesRemovedBySize": .privateValue(.unsignedInteger(bytesRemovedBySize)),
                "retainedFiles": .privateValue(.integer(Int64(retained.count))),
                "retainedBytes": .privateValue(.unsignedInteger(totalBytes))
            ]
        )
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
        let url = configuration.directory.appendingPathComponent("diagnostics-v3-\(day).jsonl")
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

    nonisolated private static func canonicalString(_ fields: [String: Field]) -> String {
        fields.keys.sorted().map { key in
            guard let field = fields[key] else { return key }
            return "\(key)=\(canonicalString(field.value))"
        }.joined(separator: "|")
    }

    nonisolated private static func canonicalString(_ value: Value) -> String {
        switch value {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .unsignedInteger(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        case .array(let values): return values.map(canonicalString).joined(separator: ",")
        case .object(let values):
            return values.keys.sorted().map { key in
                "\(key):\(values[key].map(canonicalString) ?? "null")"
            }.joined(separator: ",")
        case .null: return "null"
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

/// Process-wide semantic rate control. Events are never severity-filtered.
/// Samples use a fixed cadence; states write on change plus a sparse heartbeat;
/// throttled events write the first occurrence plus at most one per interval.
nonisolated final class DiagnosticJournalPolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var sampleInterval: TimeInterval
    private var stateHeartbeatInterval: TimeInterval
    private var lastSampleAt: [String: Date] = [:]
    private var lastStateAt: [String: Date] = [:]
    private var lastStateFingerprint: [String: String] = [:]
    private var lastThrottledAt: [String: Date] = [:]
    private var throttledSuppressed: [String: Int] = [:]

    init(
        sampleInterval: TimeInterval = DiagnosticLogService.defaultSampleInterval,
        stateHeartbeatInterval: TimeInterval = DiagnosticLogService.defaultStateHeartbeatInterval
    ) {
        self.sampleInterval = sampleInterval
        self.stateHeartbeatInterval = stateHeartbeatInterval
    }

    func reset(
        sampleInterval: TimeInterval,
        stateHeartbeatInterval: TimeInterval = DiagnosticLogService.defaultStateHeartbeatInterval
    ) {
        lock.lock()
        self.sampleInterval = sampleInterval
        self.stateHeartbeatInterval = stateHeartbeatInterval
        lastSampleAt.removeAll()
        lastStateAt.removeAll()
        lastStateFingerprint.removeAll()
        lastThrottledAt.removeAll()
        throttledSuppressed.removeAll()
        lock.unlock()
    }

    func allowsSample(category: String, action: String, at date: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(category).\(action)"
        if let last = lastSampleAt[key], date.timeIntervalSince(last) < sampleInterval {
            return false
        }
        lastSampleAt[key] = date
        return true
    }

    func allowsState(
        category: String,
        action: String,
        identity: String,
        fingerprint: String,
        at date: Date
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(category).\(action).\(identity)"
        if lastStateFingerprint[key] != fingerprint {
            lastStateFingerprint[key] = fingerprint
            lastStateAt[key] = date
            return true
        }
        guard let last = lastStateAt[key], date.timeIntervalSince(last) < stateHeartbeatInterval else {
            lastStateAt[key] = date
            return true
        }
        return false
    }

    /// `nil` means "fold into the next record"; otherwise the returned count is how many
    /// identical occurrences were swallowed since the previous emitted record.
    func throttledCount(
        category: String,
        action: String,
        identity: String,
        interval: TimeInterval,
        at date: Date
    ) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(category).\(action).\(identity)"
        let suppressed = throttledSuppressed[key] ?? 0
        if let last = lastThrottledAt[key], date.timeIntervalSince(last) < max(interval, 0) {
            throttledSuppressed[key] = suppressed + 1
            return nil
        }
        lastThrottledAt[key] = date
        throttledSuppressed[key] = 0
        return suppressed
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
                coalescedSamples["\(record.category).\(record.action)"] = record
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
