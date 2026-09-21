//
//  DiagnosticSessionIndexTests.swift
//  LightStatsTests
//
//  一份报告可能跨越多次启动甚至重启。会话索引必须把「启动了几次、有没有重启过」
//  直接写出来，而不是留给读者从时间戳和 uptime 里猜。
//

import Foundation
import XCTest
@testable import Light_Stats

final class DiagnosticSessionIndexTests: XCTestCase {

    func testSessionsAreListedWithLaunchTerminateAndUptime() throws {
        let first = "AAAAAAAA-0000-0000-0000-000000000001"
        let second = "BBBBBBBB-0000-0000-0000-000000000002"
        let records = [
            record(session: first, offset: 0, category: "application", action: "launched",
                   fields: ["version": .publicValue("1.9.5"), "build": .publicValue("2")]),
            record(session: first, offset: 1, category: "environment", action: "baseline",
                   fields: ["system.uptimeSeconds": .privateValue(.double(5_930))]),
            record(session: first, offset: 120, category: "application", action: "willTerminate"),
            // 第二次启动：系统 uptime 变小 → 期间重启过。
            record(session: second, offset: 250, category: "application", action: "launched",
                   fields: ["version": .publicValue("1.9.5"), "build": .publicValue("2")]),
            record(session: second, offset: 251, category: "environment", action: "baseline",
                   fields: ["system.uptimeSeconds": .privateValue(.double(114))])
        ]

        let index = DiagnosticSessionIndex.build(records: records)

        XCTAssertEqual(index.sessions.count, 2)
        XCTAssertEqual(index.sessions[0].sessionID, first)
        XCTAssertEqual(index.sessions[0].records, 3)
        XCTAssertEqual(index.sessions[0].version, "1.9.5")
        XCTAssertEqual(index.sessions[0].build, "2")
        XCTAssertEqual(index.sessions[0].osUptimeAtLaunchSeconds, 5_930)
        XCTAssertNotNil(index.sessions[0].terminatedAt)
        XCTAssertNil(index.sessions[1].terminatedAt, "还在跑的会话没有结束时间")
        XCTAssertLessThan(
            index.sessions[1].osUptimeAtLaunchSeconds ?? .infinity,
            index.sessions[0].osUptimeAtLaunchSeconds ?? 0,
            "uptime 变小就是重启信号，索引必须保住这个可比性"
        )
    }

    func testLegacyUptimeFieldStillReadsSoOldReportsCompare() throws {
        let legacy = record(
            session: "CCCCCCCC-0000-0000-0000-000000000003",
            offset: 0,
            category: "environment",
            action: "baseline",
            fields: ["process.uptimeSeconds": .privateValue(.double(72.5))]
        )

        let index = DiagnosticSessionIndex.build(records: [legacy])

        XCTAssertEqual(index.sessions[0].osUptimeAtLaunchSeconds, 72.5)
    }

    func testSessionsSortByFirstRecordNotByInputOrder() throws {
        let later = record(session: "DDDD", offset: 600, category: "system", action: "collected")
        let earlier = record(session: "EEEE", offset: 0, category: "system", action: "collected")

        let index = DiagnosticSessionIndex.build(records: [later, earlier])

        XCTAssertEqual(index.sessions.map(\.sessionID), ["EEEE", "DDDD"])
    }

    // MARK: - Helpers

    private func record(
        session: String,
        offset: TimeInterval,
        category: String,
        action: String,
        fields: [String: DiagnosticLogService.Field] = [:]
    ) -> DiagnosticLogService.Record {
        DiagnosticLogService.Record(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            level: .info,
            category: category,
            action: action,
            fields: fields,
            sessionID: session
        )
    }
}
