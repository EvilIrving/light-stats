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

    func testSummaryReportsTheTighterBucketOfEachWindow() throws {
        let snapshot = try AntigravityUsageService.parseQuotaSummary(fixture("antigravity_quota_summary.json"))

        XCTAssertEqual(snapshot.provider, .antigravity)
        XCTAssertEqual(snapshot.windows.map(\.label), ["5h", "7d"])
        // Gemini group: 0.9270784 / 0.9878464 left, Claude+GPT group: 1.0 left.
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 7.292, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[1].usedPercent ?? -1, 1.215, accuracy: 0.001)
        XCTAssertEqual(
            snapshot.windows[0].resetsAt,
            ISO8601DateFormatter().date(from: "2026-10-11T11:30:25Z"),
            "the 5h row keeps the tighter bucket's own reset"
        )
    }

    /// The two groups are separate allowances: whichever is more consumed is the
    /// one the user hits first, so the row must follow the used percent, not the
    /// group order.
    func testSummaryFollowsTheMoreConsumedGroup() throws {
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

        XCTAssertEqual(snapshot.windows.map(\.label), ["5h"])
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 60.0, accuracy: 0.001)
        XCTAssertEqual(
            snapshot.windows[0].resetsAt,
            ISO8601DateFormatter().date(from: "2026-10-11T11:50:39Z")
        )
    }

    func testSummaryValueDrivesTheCollapsedHeader() throws {
        let snapshot = try AntigravityUsageService.parseQuotaSummary(fixture("antigravity_quota_summary.json"))
        XCTAssertEqual(
            AIUsageWindowPicker.nearestReset(in: snapshot.windows)?.label,
            "5h",
            "the header leads with the window that resets soonest"
        )
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
