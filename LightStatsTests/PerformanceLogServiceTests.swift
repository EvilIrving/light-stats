//
//  PerformanceLogServiceTests.swift
//  LightStatsTests
//

import Foundation
import XCTest
@testable import Light_Stats

final class PerformanceLogServiceTests: XCTestCase {
    func testPerformanceRecordUsesIndependentSchemaAndSanitizesFields() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = PerformanceLogService(directory: directory)

        await service.append(
            action: "sampled",
            sessionID: "session-test",
            fields: ["path": .privateValue("\(NSHomeDirectory())/secret")],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await service.close()

        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        )
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["sessionID"] as? String, "session-test")
        XCTAssertNil(object["category"], "Performance records must not masquerade as diagnostic events")

        let fields = try XCTUnwrap(object["fields"] as? [String: Any])
        let path = try XCTUnwrap(fields["path"] as? [String: Any])
        XCTAssertEqual(path["value"] as? String, "~/secret")
    }
}
