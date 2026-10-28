//
//  AntigravityUsageTests.swift
//  Light Stats Tests
//
//  Locks the two Antigravity seams that carry a product rule: the Keychain blob
//  `agy` writes, and the quota summary collapsing its two model groups into the
//  panel's 5h / 7d rows. Fixtures are real (sanitized) responses.
//

import XCTest
@testable import Light_Stats

@MainActor
final class AntigravityUsageTests: XCTestCase {

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

    /// Wraps a grant the way go-keyring does, with the trailing newline the
    /// `security` CLI prints.
    private func keyringBlob(_ grant: [String: Any]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: grant)
        return Data(("go-keyring-base64:" + json.base64EncodedString() + "\n").utf8)
    }

    // MARK: - Credential

    func testDecodeCredentialReadsKeyringWrappedGrant() throws {
        let blob = try keyringBlob([
            "token": [
                "access_token": "ya29.test-access",
                "token_type": "Bearer",
                "refresh_token": "1//test-refresh",
                "expiry": "2026-10-11T15:30:06.635594+08:00"
            ],
            "auth_method": "consumer"
        ])

        let credential = try XCTUnwrap(AntigravityUsageService.decodeCredential(blob))
        XCTAssertEqual(credential.accessToken, "ya29.test-access")
        XCTAssertEqual(credential.refreshToken, "1//test-refresh")
        XCTAssertEqual(
            credential.expiry?.timeIntervalSince1970 ?? -1,
            1_791_703_806.635594,
            accuracy: 0.001,
            "the keychain expiry carries fractional seconds and a UTC offset"
        )
    }

    func testDecodeCredentialRejectsForeignAndIncompleteBlobs() throws {
        XCTAssertNil(
            AntigravityUsageService.decodeCredential(Data(#"{"token":{"access_token":"x"}}"#.utf8)),
            "a blob without the go-keyring marker is not an Antigravity credential"
        )

        let withoutAccessToken = try keyringBlob(["token": ["refresh_token": "1//test-refresh"]])
        XCTAssertNil(
            AntigravityUsageService.decodeCredential(withoutAccessToken),
            "a grant with no access token cannot be polled"
        )
    }

    func testDecodeCredentialDropsAnEmptyRefreshToken() throws {
        let blob = try keyringBlob(["token": ["access_token": "ya29.test-access", "refresh_token": ""]])
        let credential = try XCTUnwrap(AntigravityUsageService.decodeCredential(blob))
        XCTAssertNil(credential.refreshToken, "an empty refresh token is absence, not a value")
        XCTAssertNil(credential.expiry, "an absent expiry stays unknown")
    }

    // MARK: - Quota summary

    func testSummaryReportsTheTighterWindowOfEachPool() throws {
        let snapshot = try AntigravityUsageService.parseQuotaSummary(fixture("antigravity_quota_summary.json"))

        XCTAssertEqual(snapshot.provider, .antigravity)
        XCTAssertEqual(snapshot.windows.map(\.label), ["Gemini", "Claude/GPT"])
        // Gemini pool: 5h (0.927 left) is more consumed than weekly (0.988 left).
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 7.292, accuracy: 0.001)
        // Claude/GPT pool: both buckets full (1.0 left), so nothing consumed.
        XCTAssertEqual(snapshot.windows[1].usedPercent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(
            snapshot.windows[0].resetsAt,
            ISO8601DateFormatter().date(from: "2026-10-11T11:30:25Z"),
            "the Gemini row keeps its most-consumed bucket's own reset"
        )
    }

    /// The two pools are independent allowances; each row reports its own pool's
    /// bucket rather than collapsing the two pools into one number.
    func testSummaryKeepsBothPoolsSeparate() throws {
        let payload = """
        {
          "groups": [
            {
              "displayName": "Gemini Models",
              "buckets": [
                {"bucketId": "gemini-5h", "window": "5h", "remainingFraction": 0.9,
                 "resetTime": "2026-10-11T11:30:25Z"}
              ]
            },
            {
              "displayName": "Claude and GPT models",
              "buckets": [
                {"bucketId": "3p-5h", "window": "5h", "remainingFraction": 0.4,
                 "resetTime": "2026-10-11T11:50:39Z"}
              ]
            }
          ]
        }
        """

        let snapshot = try AntigravityUsageService.parseQuotaSummary(Data(payload.utf8))

        XCTAssertEqual(snapshot.windows.map(\.label), ["Gemini", "Claude/GPT"])
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 10.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[1].usedPercent ?? -1, 60.0, accuracy: 0.001)
        XCTAssertEqual(
            snapshot.windows[1].resetsAt,
            ISO8601DateFormatter().date(from: "2026-10-11T11:50:39Z")
        )
    }

    func testSummaryValueDrivesTheCollapsedHeader() throws {
        let snapshot = try AntigravityUsageService.parseQuotaSummary(fixture("antigravity_quota_summary.json"))
        XCTAssertEqual(
            AIUsageWindowPicker.nearestReset(in: snapshot.windows)?.label,
            "Gemini",
            "the header leads with the pool that resets soonest"
        )
    }

    // MARK: - Per-model quota

    func testQuotaParsesPerModelBucketsIntoFamilyWindows() throws {
        let payload = """
        {
          "buckets": [
            {"modelId": "gemini-2.5-flash", "remainingFraction": 0.87, "resetTime": "2026-10-28T12:56:11Z"},
            {"modelId": "gemini-3-flash", "remainingFraction": 0.90, "resetTime": "2026-10-28T12:56:11Z"},
            {"modelId": "claude-sonnet-4-6", "remainingFraction": 1, "resetTime": "2026-10-28T14:05:00Z"}
          ]
        }
        """

        let windows = try AntigravityUsageService.parseQuota(Data(payload.utf8))

        XCTAssertEqual(windows.map(\.label), ["Gemini", "Claude/GPT"], "one row per model family")
        XCTAssertEqual(windows[0].usedPercent ?? -1, 13.0, accuracy: 0.001)
        XCTAssertEqual(windows[1].usedPercent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(
            windows[0].resetsAt,
            ISO8601DateFormatter().date(from: "2026-10-28T12:56:11Z"),
            "the gemini family reports its most-consumed bucket (0.87), not 0.90"
        )
    }

    func testQuotaSkipsNonModelAndResetlessBuckets() throws {
        let payload = """
        {
          "buckets": [
            {"modelId": "gemini-2.5-flash", "remainingFraction": 0.5, "resetTime": "2026-10-28T12:56:11Z"},
            {"modelId": "chat_20706", "remainingFraction": 0.1, "resetTime": "2026-10-28T12:00:00Z"},
            {"modelId": "tab_flash_lite_preview", "remainingFraction": 0.1, "resetTime": "2026-10-28T12:00:00Z"},
            {"modelId": "gemini-3-flash", "remainingFraction": 0.2}
          ]
        }
        """

        let windows = try AntigravityUsageService.parseQuota(Data(payload.utf8))

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].label, "Gemini")
        XCTAssertEqual(windows[0].usedPercent ?? -1, 50.0, accuracy: 0.001)
    }

    func testMergeTakesTheMoreConsumedWindowPerPool() throws {
        let summary = [
            UsageWindow(label: "Gemini", usedPercent: 7.3, resetsAt: nil),
            UsageWindow(label: "Claude/GPT", usedPercent: 0, resetsAt: nil)
        ]
        let perModel = [
            UsageWindow(label: "Gemini", usedPercent: 12.6, resetsAt: nil),
            UsageWindow(label: "Claude/GPT", usedPercent: 0, resetsAt: nil)
        ]

        let merged = AntigravityUsageService.merge(summary, perModel)

        XCTAssertEqual(merged.map(\.label), ["Gemini", "Claude/GPT"])
        XCTAssertEqual(merged[0].usedPercent ?? -1, 12.6, accuracy: 0.001)
        XCTAssertEqual(merged[1].usedPercent ?? -1, 0, accuracy: 0.001)
    }

    func testMergeKeepsSummaryWhenPerModelIsEmpty() {
        let summary = [UsageWindow(label: "Gemini", usedPercent: 7.3, resetsAt: nil)]
        XCTAssertEqual(AntigravityUsageService.merge(summary, []).map(\.label), ["Gemini"])
    }

    // MARK: - Rejections

    func testSummaryWithoutUsableBucketsThrowsDecoding() throws {
        assertDecodingError(
            try AntigravityUsageService.parseQuotaSummary(fixture("antigravity_quota_empty.json")),
            "an empty group list leaves nothing to report"
        )
        assertDecodingError(
            try AntigravityUsageService.parseQuotaSummary(fixture("antigravity_quota_malformed.json")),
            "a malformed body should throw .decoding"
        )
    }

    func testSummarySkipsUnknownWindowKindsAndEmptyBuckets() throws {
        let payload = """
        {
          "groups": [
            {
              "buckets": [
                {"bucketId": "gemini-daily", "window": "daily", "remainingFraction": 0.5},
                {"bucketId": "gemini-weekly", "window": "weekly"}
              ]
            }
          ]
        }
        """

        assertDecodingError(
            try AntigravityUsageService.parseQuotaSummary(Data(payload.utf8)),
            "a window the panel has no row for is skipped rather than guessed at"
        )
    }
}
