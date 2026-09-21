//
//  DiagnosticJournalSummaryTests.swift
//  LightStatsTests
//
//  支持报告要能自证内容：计数、覆盖范围、原因码分布。这里钉住摘要的产出口径。
//

import Foundation
import XCTest
@testable import Light_Stats

final class DiagnosticJournalSummaryTests: XCTestCase {

    private let firstSession = "11111111-1111-1111-1111-111111111111"

    func testSummaryCountsLevelsCategoriesActionsAndProbeReasons() throws {
        let lines = [
            try line(record(category: "probe", action: "fanSpeed", level: .warning, reason: "noFanKeys")),
            try line(record(category: "probe", action: "fanSpeed", level: .warning, reason: "noFanKeys")),
            try line(record(category: "probe", action: "batteryHealth", level: .warning, reason: "missingDesignCapacity")),
            try line(record(category: "system", action: "collected", level: .info)),
            "{\"category\":\"truncated\""
        ]
        let input = DiagnosticJournalSummary.FileInput(
            name: "diagnostics-v3-test.jsonl",
            bytes: 1_024,
            copiedLines: lines,
            excludedRecords: 3
        )

        let digest = DiagnosticJournalSummary.build(files: [input])

        XCTAssertEqual(digest.summary.totalRecords, 4)
        XCTAssertEqual(digest.summary.unparsableRows, 1, "截断的行要被计数，而不是静默丢掉")
        XCTAssertEqual(digest.summary.excludedRecords, 3)
        XCTAssertEqual(digest.summary.levels["warning"], 3)
        XCTAssertEqual(digest.summary.levels["info"], 1)
        XCTAssertEqual(digest.summary.categories["probe"], 3)
        XCTAssertEqual(digest.summary.actions["system/collected"], 1)
        XCTAssertEqual(digest.summary.actions["probe/fanSpeed"], 2)
        // 读报告的人应该一眼看出「风扇是 noFanKeys，电池是 missingDesignCapacity」。
        XCTAssertEqual(digest.summary.probeReasons["fanSpeed|noFanKeys"], 2)
        XCTAssertEqual(digest.summary.probeReasons["batteryHealth|missingDesignCapacity"], 1)
        XCTAssertEqual(digest.summary.files.count, 1)
        XCTAssertEqual(digest.summary.files[0].records, 4)
        XCTAssertEqual(digest.summary.files[0].unparsableRows, 1)
        XCTAssertEqual(digest.summary.files[0].excludedRecords, 3)
    }

    func testSummaryCoverageSpansEveryFile() throws {
        let early = DiagnosticJournalSummary.FileInput(
            name: "diagnostics-v3-early.jsonl",
            bytes: 10,
            copiedLines: [try line(record(category: "system", action: "collected", level: .info, offset: 0))],
            excludedRecords: 0
        )
        let late = DiagnosticJournalSummary.FileInput(
            name: "diagnostics-v3-late.jsonl",
            bytes: 20,
            copiedLines: [try line(record(category: "system", action: "collected", level: .info, offset: 7_200))],
            excludedRecords: 1
        )

        let digest = DiagnosticJournalSummary.build(files: [early, late])

        XCTAssertEqual(digest.summary.totalRecords, 2)
        XCTAssertEqual(digest.summary.excludedRecords, 1)
        XCTAssertEqual(
            digest.summary.firstAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(
            digest.summary.lastAt,
            Date(timeIntervalSince1970: 1_700_007_200)
        )
    }

    func testDetectedProbeReasonsUseTheReportedReasonCode() throws {
        let lines = [
            try line(record(category: "probe", action: "fanSpeed", level: .warning, reason: "noFanKeys")),
            // 成功记录也带 reasonCode（valueRead），摘要要如实反映而不是只统计失败。
            try line(record(category: "probe", action: "gpuUtilization", level: .info, reason: "valueRead"))
        ]

        let digest = DiagnosticJournalSummary.build(files: [DiagnosticJournalSummary.FileInput(
            name: "diagnostics-v3-test.jsonl",
            bytes: 1,
            copiedLines: lines,
            excludedRecords: 0
        )])

        XCTAssertEqual(digest.summary.probeReasons["gpuUtilization|valueRead"], 1)
    }

    // MARK: - Helpers

    private func record(
        category: String,
        action: String,
        level: DiagnosticLogService.Level,
        reason: String? = nil,
        offset: TimeInterval = 0
    ) -> DiagnosticLogService.Record {
        var fields: [String: DiagnosticLogService.Field] = [:]
        if let reason {
            fields["reasonCode"] = .publicValue(reason)
        }
        return DiagnosticLogService.Record(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            level: level,
            category: category,
            action: action,
            fields: fields,
            sessionID: firstSession
        )
    }

    private func line(_ record: DiagnosticLogService.Record) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(record), as: UTF8.self)
    }
}
