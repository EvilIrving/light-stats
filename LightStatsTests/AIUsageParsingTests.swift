//
//  AIUsageParsingTests.swift
//  Light Stats Tests
//
//  Locks the current behavior of the three AI-usage response parsers against
//  sanitized JSON fixtures. This is the regression baseline for the P4 service
//  refactor: the parse functions must keep mapping identical bytes to identical
//  windows. Fixtures live in ./Fixtures and are loaded straight off disk via
//  #filePath — no bundle-resource wiring needed.
//

import XCTest
@testable import Light_Stats

@MainActor
final class AIUsageParsingTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    private func assertDecodingError(_ expression: @autoclosure () throws -> Any, _ message: String) {
        XCTAssertThrowsError(try expression(), message) { error in
            XCTAssertEqual(error as? AIUsageError, .decoding, "expected .decoding, got \(error)")
        }
    }

    // MARK: - Claude

    func testClaudeParsesBothWindows() throws {
        let windows = try ClaudeUsageService.parseUsageJSON(fixture("claude_usage_full.json"))
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].label, "5h")
        XCTAssertEqual(windows[0].usedPercent, 42.5, accuracy: 0.001)
        XCTAssertNotNil(windows[0].resetsAt)
        XCTAssertEqual(windows[1].label, "7d")
        XCTAssertEqual(windows[1].usedPercent, 12.0, accuracy: 0.001)
        XCTAssertNotNil(windows[1].resetsAt, "fractional-seconds ISO timestamp should parse")
    }

    func testClaudeParsesPartialResponse() throws {
        let windows = try ClaudeUsageService.parseUsageJSON(fixture("claude_usage_partial.json"))
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].label, "5h")
        XCTAssertEqual(windows[0].usedPercent, 88.0, accuracy: 0.001)
    }

    func testClaudeDropsWindowsWithoutUtilization() throws {
        // Windows present but no utilization field -> nothing usable, empty (not an error here).
        let windows = try ClaudeUsageService.parseUsageJSON(fixture("claude_usage_no_utilization.json"))
        XCTAssertTrue(windows.isEmpty)
    }

    func testClaudeMalformedThrowsDecoding() throws {
        assertDecodingError(try ClaudeUsageService.parseUsageJSON(fixture("claude_usage_malformed.json")),
                            "malformed Claude JSON should throw .decoding")
    }

    // MARK: - Codex

    func testCodexParsesBothWindows() throws {
        let windows = try CodexUsageService.parseUsageJSON(fixture("codex_usage_full.json"))
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].label, "5h")           // 18000s -> "5h"
        XCTAssertEqual(windows[0].usedPercent, 37.0, accuracy: 0.001)
        XCTAssertNotNil(windows[0].resetsAt)
        XCTAssertEqual(windows[1].label, "7d")           // 604800s -> "7d"
        XCTAssertEqual(windows[1].usedPercent, 9.5, accuracy: 0.001)
    }

    func testCodexParsesPrimaryOnly() throws {
        let windows = try CodexUsageService.parseUsageJSON(fixture("codex_usage_primary_only.json"))
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].label, "5h")
    }

    func testCodexDropsWindowsWithoutUsedPercent() throws {
        let windows = try CodexUsageService.parseUsageJSON(fixture("codex_usage_no_percent.json"))
        XCTAssertTrue(windows.isEmpty)
    }

    func testCodexMalformedThrowsDecoding() throws {
        assertDecodingError(try CodexUsageService.parseUsageJSON(fixture("codex_usage_malformed.json")),
                            "malformed Codex JSON should throw .decoding")
    }

    // MARK: - Gemini

    func testGeminiParsesProFlashLiteWindows() throws {
        let snapshot = try GeminiUsageService.parseQuotaResponse(fixture("gemini_quota_full.json"))
        XCTAssertEqual(snapshot.provider, .gemini)
        XCTAssertEqual(snapshot.windows.map(\.label), ["Pro", "Flash", "Lite"])
        // usedPercent = 100 - remainingFraction*100.
        XCTAssertEqual(snapshot.windows[0].usedPercent, 20.0, accuracy: 0.001)  // pro 0.80 left
        XCTAssertEqual(snapshot.windows[1].usedPercent, 50.0, accuracy: 0.001)  // flash 0.50 left
        XCTAssertEqual(snapshot.windows[2].usedPercent, 5.0, accuracy: 0.001)   // lite 0.95 left
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
    }

    func testGeminiEmptyQuotasThrowsDecoding() throws {
        assertDecodingError(try GeminiUsageService.parseQuotaResponse(fixture("gemini_quota_empty.json")),
                            "no quotas should throw .decoding")
    }

    func testGeminiMalformedThrowsDecoding() throws {
        assertDecodingError(try GeminiUsageService.parseQuotaResponse(fixture("gemini_quota_malformed.json")),
                            "malformed Gemini JSON should throw .decoding")
    }
}
