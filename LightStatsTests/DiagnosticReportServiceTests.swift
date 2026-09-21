//
//  DiagnosticReportServiceTests.swift
//  LightStatsTests
//

import Foundation
import XCTest
@testable import Light_Stats

final class DiagnosticReportServiceTests: XCTestCase {
    func testReportArchiveContainsContextSettingsAndJournalButNoPerformanceData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent("journal-source", isDirectory: true)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        try writeJournal(
            [
                record(category: "application", action: "launched", fields: [
                    "version": .publicValue("1.9.5"),
                    "build": .publicValue("2")
                ]),
                record(category: "system", action: "collected"),
                record(category: "probe", action: "fanSpeed", level: .warning, fields: [
                    "reasonCode": .publicValue("noFanKeys")
                ])
            ],
            to: journal.appendingPathComponent("diagnostics-v3-test.jsonl")
        )

        let destination = root.appendingPathComponent("report.zip")
        let service = DiagnosticReportService(
            journalDirectory: journal,
            collectsFreshProbes: false,
            recordsLifecycleEvents: false
        )
        let reportURL = try await service.createReport(
            at: destination,
            settings: ["theme": "noir"]
        )

        let archiveData = try Data(contentsOf: reportURL)
        XCTAssertEqual(Array(archiveData.prefix(2)), [0x50, 0x4B])

        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try extract(reportURL, to: extracted)
        let reportRoot = extracted.appendingPathComponent("Light Stats Diagnostics", isDirectory: true)

        for filename in [
            "manifest.json", "environment.json", "settings.json",
            "capabilities.json", "summary.json", "sessions.json"
        ] {
            let url = reportRoot.appendingPathComponent(filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing \(filename)")
            _ = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: reportRoot.appendingPathComponent("journal/diagnostics-v3-test.jsonl").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: reportRoot.appendingPathComponent("Performance Recordings").path
        ))

        let manifest = try jsonObject(at: reportRoot.appendingPathComponent("manifest.json"))
        XCTAssertEqual(manifest["reportSchemaVersion"] as? Int, DiagnosticReportService.reportSchemaVersion)
        XCTAssertNotNil(manifest["journalPolicy"], "报告必须声明保留策略，才能解释「为什么没有更早的记录」")
        XCTAssertEqual(manifest["journalExcludedCategories"] as? [String], ["selfMonitoring"])
        let journalFiles = try XCTUnwrap(manifest["journalFiles"] as? [[String: Any]])
        XCTAssertEqual(journalFiles.count, 1)
        XCTAssertEqual(journalFiles[0]["name"] as? String, "diagnostics-v3-test.jsonl")
        XCTAssertEqual(journalFiles[0]["excludedRecords"] as? Int, 0)

        let summary = try jsonObject(at: reportRoot.appendingPathComponent("summary.json"))
        XCTAssertEqual(summary["totalRecords"] as? Int, 3)
        XCTAssertEqual(summary["unparsableRows"] as? Int, 0)
        let probeReasons = try XCTUnwrap(summary["probeReasons"] as? [String: Int])
        XCTAssertEqual(probeReasons["fanSpeed|noFanKeys"], 1, "摘要要能一眼回答「风扇为什么没有值」")

        let sessions = try jsonObject(at: reportRoot.appendingPathComponent("sessions.json"))
        let sessionList = try XCTUnwrap(sessions["sessions"] as? [[String: Any]])
        XCTAssertEqual(sessionList.count, 1)
        XCTAssertEqual(sessionList[0]["version"] as? String, "1.9.5")
    }

    func testExcludedCategoriesStayOutOfTheReportAndAreDeclaredExcluded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent("journal-source", isDirectory: true)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        try writeJournal(
            [
                record(category: "selfMonitoring", action: "sampled"),
                record(category: "system", action: "collected")
            ],
            to: journal.appendingPathComponent("diagnostics-v3-test.jsonl")
        )

        let reportURL = try await DiagnosticReportService(
            journalDirectory: journal,
            collectsFreshProbes: false,
            recordsLifecycleEvents: false
        ).createReport(at: root.appendingPathComponent("report.zip"), settings: [:])

        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try extract(reportURL, to: extracted)
        let reportRoot = extracted.appendingPathComponent("Light Stats Diagnostics", isDirectory: true)

        let copied = try String(
            contentsOf: reportRoot.appendingPathComponent("journal/diagnostics-v3-test.jsonl"),
            encoding: .utf8
        )
        XCTAssertFalse(copied.contains("selfMonitoring"))
        XCTAssertTrue(copied.contains("system"))
        let manifest = try jsonObject(at: reportRoot.appendingPathComponent("manifest.json"))
        let journalFiles = try XCTUnwrap(manifest["journalFiles"] as? [[String: Any]])
        XCTAssertEqual(journalFiles[0]["excludedRecords"] as? Int, 1)
        let summary = try jsonObject(at: reportRoot.appendingPathComponent("summary.json"))
        XCTAssertEqual(summary["excludedRecords"] as? Int, 1)
        XCTAssertEqual(summary["totalRecords"] as? Int, 1)
    }

    func testCapabilitiesCarryTheReasonWhenNoValueWasCollected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let reportURL = try await DiagnosticReportService(
            journalDirectory: root.appendingPathComponent("missing-journal", isDirectory: true),
            collectsFreshProbes: false,
            recordsLifecycleEvents: false
        ).createReport(at: root.appendingPathComponent("report.zip"), settings: [:])

        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try extract(reportURL, to: extracted)
        let reportRoot = extracted.appendingPathComponent("Light Stats Diagnostics", isDirectory: true)

        let capabilities = try jsonObject(at: reportRoot.appendingPathComponent("capabilities.json"))
        XCTAssertEqual(capabilities["probeCollectionEnabled"] as? Bool, false)
        let fan = try XCTUnwrap(capabilities["fan"] as? [String: Any])
        XCTAssertEqual(fan["available"] as? Bool, false)
        XCTAssertEqual(fan["reasonCode"] as? String, "notCollected", "没有采集和读不到必须分开写")
        let gpu = try XCTUnwrap(capabilities["gpu"] as? [String: Any])
        XCTAssertEqual(gpu["reasonCode"] as? String, "notCollected")
        let temperature = try XCTUnwrap(capabilities["cpuTemperature"] as? [String: Any])
        XCTAssertEqual(temperature["reasonCode"] as? String, "notCollected")
        let battery = try XCTUnwrap(capabilities["battery"] as? [String: Any])
        XCTAssertEqual(battery["reasonCodes"] as? [String: String], ["all": "notCollected"])

        let environment = try jsonObject(at: reportRoot.appendingPathComponent("environment.json"))
        XCTAssertNotNil(environment["system.uptimeSeconds"], "开机时长要写清是系统的，不是本进程的")
        XCTAssertNil(environment["process.uptimeSeconds"])
        XCTAssertNotNil(environment["os.versionNumber"], "本地化的 os.version 之外要有可解析版本号")
    }

    func testDiagnosticValueConvertsIntoJSONSerializableObjects() throws {
        // 取证数组要真的进得去 JSONSerialization：把 Value 装箱成枚举描述会在这里炸掉。
        let value = DiagnosticLogService.Value.array([
            .object([
                "key": .string("F0Ac"),
                "present": .bool(true),
                "value": .integer(2_500),
                "rpm": .null
            ])
        ])

        let json = DiagnosticReportService.jsonValue(value)
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        XCTAssertEqual(decoded.first?["key"] as? String, "F0Ac")
        XCTAssertEqual(decoded.first?["present"] as? Bool, true)
        XCTAssertEqual(decoded.first?["value"] as? Int, 2_500)
        XCTAssertTrue(decoded.first?["rpm"] is NSNull)
    }

    // MARK: - Helpers

    private func record(
        category: String,
        action: String,
        level: DiagnosticLogService.Level = .info,
        fields: [String: DiagnosticLogService.Field] = [:]
    ) -> DiagnosticLogService.Record {
        DiagnosticLogService.Record(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            level: level,
            category: category,
            action: action,
            fields: fields,
            sessionID: "TEST-SESSION"
        )
    }

    private func writeJournal(_ records: [DiagnosticLogService.Record], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = try records
            .map { String(decoding: try encoder.encode($0), as: UTF8.self) }
            .joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private func extract(_ archive: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
