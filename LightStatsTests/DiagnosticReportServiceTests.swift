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
        try Data("{\"category\":\"test\"}\n".utf8).write(
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

        for filename in ["manifest.json", "environment.json", "settings.json", "capabilities.json"] {
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
