//
//  PerformanceLogService.swift
//  Light Stats
//
//  Explicit, user-started product performance recording. This storage is
//  intentionally separate from diagnostic support logs and support reports.
//

import Foundation

actor PerformanceLogService {
    private struct Record: Codable, Sendable {
        let schemaVersion: Int
        let timestamp: Date
        let sessionID: String
        let action: String
        let fields: [String: DiagnosticLogService.Field]

        init(
            timestamp: Date,
            sessionID: String,
            action: String,
            fields: [String: DiagnosticLogService.Field]
        ) {
            schemaVersion = 1
            self.timestamp = timestamp
            self.sessionID = sessionID
            self.action = action
            self.fields = fields
        }
    }

    static let shared = PerformanceLogService()

    nonisolated static var recordingsDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Light Stats/Performance Recordings", isDirectory: true)
    }

    private static let logger = AppLogger(category: "PerformanceRecording", mirrorsToJournal: false)
    private static let retentionDays = 14

    private let encoder: JSONEncoder
    private let directory: URL
    private var currentDay: String?
    private var currentHandle: FileHandle?

    init(directory: URL = PerformanceLogService.recordingsDirectoryURL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    nonisolated static func record(
        action: String,
        sessionID: String,
        fields: [String: DiagnosticLogService.Field]
    ) {
        Task {
            await shared.append(
                action: action,
                sessionID: sessionID,
                fields: fields
            )
        }
    }

    func append(
        action: String,
        sessionID: String,
        fields: [String: DiagnosticLogService.Field],
        timestamp: Date = Date()
    ) {
        let record = Record(
            timestamp: timestamp,
            sessionID: sessionID,
            action: action,
            fields: DiagnosticLogService.sanitized(fields)
        )
        append(record)
    }

    func flush() {
        do {
            try currentHandle?.synchronize()
        } catch {
            Self.logger.error("Performance recording flush failed: \(error.localizedDescription)")
        }
    }

    func close() {
        flush()
        try? currentHandle?.close()
        currentHandle = nil
        currentDay = nil
    }

    private func append(_ record: Record) {
        do {
            try prepareDirectory()
            try rotateIfNeeded(for: record.timestamp)
            var data = try encoder.encode(record)
            data.append(0x0A)
            try currentHandle?.write(contentsOf: data)
        } catch {
            Self.logger.error("Performance recording write failed: \(error.localizedDescription)")
        }
    }

    private func prepareDirectory() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func rotateIfNeeded(for date: Date) throws {
        let day = Self.dayString(date)
        guard currentDay != day || currentHandle == nil else { return }
        try currentHandle?.close()
        try cleanUp(referenceDate: date)

        let url = directory.appendingPathComponent("performance-v1-\(day).jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        currentHandle = handle
        currentDay = day
    }

    private func cleanUp(referenceDate: Date) throws {
        let fileManager = FileManager.default
        let expiration = referenceDate.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        for url in urls where url.lastPathComponent.hasPrefix("performance-") {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            if values.contentModificationDate.map({ $0 < expiration }) == true {
                try fileManager.removeItem(at: url)
            }
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
}
