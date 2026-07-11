//
//  DiagnosticLogServiceTests.swift
//  LightStatsTests
//

import XCTest
@testable import Light_Stats

final class DiagnosticLogServiceTests: XCTestCase {

    func testAppendWritesDecodableJSONLine() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(directory: directory)
        let record = DiagnosticLogService.Record(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            level: .info,
            category: "test",
            action: "sampled",
            fields: ["cpu": .privateValue(.integer(42))]
        )

        await service.append(record)
        await service.flush()

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let lines = try String(contentsOf: files[0], encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let decoded = try JSONDecoder.withISO8601Dates.decode(
            DiagnosticLogService.Record.self,
            from: Data(lines[0].utf8)
        )
        XCTAssertEqual(decoded.category, "test")
        XCTAssertEqual(decoded.fields["cpu"], .privateValue(.integer(42)))
    }

    func testConcurrentAppendWritesEveryRecord() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(directory: directory)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    await service.append(DiagnosticLogService.Record(
                        timestamp: timestamp,
                        level: .info,
                        category: "concurrency",
                        action: "append",
                        fields: ["index": .privateValue(.integer(Int64(index)))]
                    ))
                }
            }
        }
        await service.close()

        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).first)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 100)
    }

    func testPrivacyFilterRedactsSecretsAndPersonalData() {
        let fields = DiagnosticLogService.sanitized([
            "secret": .secret,
            "stderr": .privateValue("Bearer abc.def user@example.com \(NSHomeDirectory()) sk-abcdefgh12345678")
        ])

        XCTAssertEqual(fields["secret"], .secret)
        guard case .string(let stderr) = fields["stderr"]?.value else {
            return XCTFail("Expected sanitized string")
        }
        XCTAssertFalse(stderr.contains("abc.def"))
        XCTAssertFalse(stderr.contains("user@example.com"))
        XCTAssertFalse(stderr.contains(NSHomeDirectory()))
        XCTAssertFalse(stderr.contains("sk-abcdefgh12345678"))
    }

    func testSampleBackpressureDoesNotDependOnCategorySuffix() {
        let buffer = DiagnosticRecordBuffer()
        for index in 0..<300 {
            _ = buffer.enqueue(makeRecord(category: "metric", index: index), kind: .sample)
        }

        let records = drain(buffer)

        XCTAssertEqual(records.filter { $0.category == "metric" }.count, 257)
        XCTAssertTrue(records.contains { $0.category == "logging" && $0.action == "backpressure" })
    }

    func testImportantBackpressureBoundsQueueAndRecordsDroppedCount() {
        let buffer = DiagnosticRecordBuffer()
        for index in 0..<2_050 {
            _ = buffer.enqueue(makeRecord(category: "event", index: index), kind: .important)
        }

        let records = drain(buffer)
        let backpressure = records.first { $0.category == "logging" && $0.action == "backpressure" }

        XCTAssertEqual(records.count, 2_048)
        XCTAssertEqual(backpressure?.fields["droppedImportantCount"], .publicValue("3"))
    }

    func testFileAndDirectoryPermissionsArePrivate() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(directory: directory)
        await service.append(makeRecord(timestamp: Date(timeIntervalSince1970: 1_700_000_000)))
        await service.close()

        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).first)
        let directoryMode = try permissionMode(at: directory)
        let fileMode = try permissionMode(at: file)
        XCTAssertEqual(directoryMode, 0o700)
        XCTAssertEqual(fileMode, 0o600)
    }

    func testAppendRotatesAtUTCDayBoundary() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(directory: directory)
        await service.append(makeRecord(timestamp: Date(timeIntervalSince1970: 1_700_006_399)))
        await service.append(makeRecord(timestamp: Date(timeIntervalSince1970: 1_700_006_401)))
        await service.close()

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
    }

    func testCleanupDeletesFilesOlderThanFiveDays() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = directory.appendingPathComponent("diagnostics-old.jsonl")
        let recent = directory.appendingPathComponent("diagnostics-recent.jsonl")
        FileManager.default.createFile(atPath: old.path, contents: Data("old".utf8))
        FileManager.default.createFile(atPath: recent.path, contents: Data("recent".utf8))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-6 * 86_400)],
            ofItemAtPath: old.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-4 * 86_400)],
            ofItemAtPath: recent.path
        )
        let service = makeService(directory: directory)

        try await service.cleanUp(referenceDate: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
    }

    func testCleanupRemovesOldestFilesOverCapacity() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let older = directory.appendingPathComponent("diagnostics-older.jsonl")
        let newer = directory.appendingPathComponent("diagnostics-newer.jsonl")
        FileManager.default.createFile(atPath: older.path, contents: Data(repeating: 1, count: 80))
        FileManager.default.createFile(atPath: newer.path, contents: Data(repeating: 2, count: 80))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-100)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: newer.path)
        let service = makeService(directory: directory, maximumBytes: 100)

        try await service.cleanUp(referenceDate: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: older.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newer.path))
    }

    private func makeService(directory: URL, maximumBytes: UInt64 = 1_024) -> DiagnosticLogService {
        DiagnosticLogService(configuration: .init(
            directory: directory,
            retentionDays: 5,
            maximumBytes: maximumBytes
        ))
    }

    private func makeRecord(timestamp: Date) -> DiagnosticLogService.Record {
        DiagnosticLogService.Record(
            timestamp: timestamp,
            level: .info,
            category: "test",
            action: "append",
            fields: [:]
        )
    }

    private func makeRecord(category: String, index: Int) -> DiagnosticLogService.Record {
        DiagnosticLogService.Record(
            timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
            level: .info,
            category: category,
            action: "recorded",
            fields: ["index": .privateValue(.integer(Int64(index)))]
        )
    }

    private func drain(_ buffer: DiagnosticRecordBuffer) -> [DiagnosticLogService.Record] {
        var records: [DiagnosticLogService.Record] = []
        while let batch = buffer.nextBatch() {
            records.append(contentsOf: batch)
        }
        return records
    }

    private func permissionMode(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? Int) & 0o777
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private extension JSONDecoder {
    static var withISO8601Dates: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
