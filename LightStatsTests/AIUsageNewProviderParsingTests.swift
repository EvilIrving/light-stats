//
//  AIUsageNewProviderParsingTests.swift
//  Light Stats Tests
//

import SQLite3
import XCTest
@testable import Light_Stats

@MainActor
final class AIUsageNewProviderParsingTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    func testDeepSeekPicksPositiveCNYAndNeverBuildsWindows() throws {
        let snapshot = try DeepSeekUsageService.parseBalanceJSON(fixture("deepseek_balance_cny.json"))
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertEqual(snapshot.balance?.currency, "CNY")
        XCTAssertEqual(snapshot.balance?.total, "110.00")
        XCTAssertEqual(snapshot.balance?.granted, "10.00")
        XCTAssertEqual(snapshot.balance?.toppedUp, "100.00")
        XCTAssertEqual(snapshot.balance?.isAvailable, true)
    }

    func testDeepSeekUnavailableStillReturnsBalance() throws {
        let snapshot = try DeepSeekUsageService.parseBalanceJSON(fixture("deepseek_balance_unavailable.json"))
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertEqual(snapshot.balance?.isAvailable, false)
        XCTAssertEqual(snapshot.balance?.total, "0.50")
    }

    func testGrokPercentAndOnDemandWindows() throws {
        let percent = try GrokUsageService.parseBillingJSON(fixture("grok_billing_percent.json"))
        XCTAssertEqual(percent.windows.count, 1)
        XCTAssertEqual(percent.windows[0].usedPercent ?? -1, 38.5, accuracy: 0.001)
        XCTAssertNotNil(percent.windows[0].resetsAt)
        XCTAssertNil(percent.balance)

        let onDemand = try GrokUsageService.parseBillingJSON(fixture("grok_billing_ondemand.json"))
        XCTAssertEqual(onDemand.windows[0].usedPercent ?? -1, 25, accuracy: 0.001)
    }

    func testGrokPeriodOnlyTreatsOmittedPercentAsZero() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-15T00:00:00Z"))
        let snapshot = try GrokUsageService.parseBillingJSON(fixture("grok_billing_period_only.json"), now: now)
        XCTAssertEqual(snapshot.windows[0].label, "7d")
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 0, accuracy: 0.001)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
    }

    func testGrokPeriodOnlyOutsideWindowStaysUnknown() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-21T00:00:00Z"))
        let snapshot = try GrokUsageService.parseBillingJSON(fixture("grok_billing_period_only.json"), now: now)
        XCTAssertEqual(snapshot.windows[0].label, "7d")
        XCTAssertNil(snapshot.windows[0].usedPercent)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
    }

    func testGrokLedgerMonthlyPercentFillsMissingCreditsPercent() throws {
        let snapshot = try GrokUsageService.parseBillingJSON(
            fixture("grok_billing_period_only.json"),
            ledger: fixture("grok_billing_monthly.json")
        )
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 17, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[0].label, UsageWindowLabel.month.key)
    }

    func testGrokProductUsageSuppliesPercentWhenWeeklyOmitted() throws {
        let snapshot = try GrokUsageService.parseBillingJSON(fixture("grok_billing_product_usage.json"))
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 34, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[0].label, "7d")
    }

    func testGrokAuthPrefersOIDCKey() {
        let json: [String: Any] = [
            "https://accounts.x.ai/sign-in": ["key": "legacy"],
            "https://auth.x.ai::abc": ["key": "oidc-token"]
        ]
        XCTAssertEqual(GrokUsageService.parseAuthJSON(json), "oidc-token")
    }

    func testZAIMapsPercentWindowAndCreditBalance() throws {
        let snapshot = try ZAIUsageService.parseQuotaJSON(fixture("zai_quota_windows.json"))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].label, "5h")
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 42, accuracy: 0.001)
        XCTAssertEqual(snapshot.balance?.currency, "USD")
        XCTAssertEqual(snapshot.balance?.total, "12.5")
    }

    func testZAINoCodingPlanQuotaThrows() {
        XCTAssertThrowsError(try ZAIUsageService.parseQuotaJSON(fixture("zai_no_coding_plan.json"))) { error in
            XCTAssertEqual(error as? AIUsageError, .decoding)
        }
    }

    func testZAIAccountReportMapsAvailableBalance() throws {
        let snapshot = try ZAIUsageService.parseAccountJSON(fixture("zai_account_report.json"))
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertEqual(snapshot.balance?.currency, "CNY")
        XCTAssertEqual(snapshot.balance?.total, "27.29")
        XCTAssertEqual(snapshot.balance?.granted, "51.84")
        XCTAssertEqual(snapshot.balance?.toppedUp, "0.00")
        XCTAssertEqual(snapshot.balance?.isAvailable, true)
    }

    func testGrokShortLabelUses5hWhenResetIsSoon() {
        let soon = Date().addingTimeInterval(25 * 60)
        XCTAssertEqual(GrokUsageService.shortWindowLabel(until: soon), "5h")
        let week = Date().addingTimeInterval(5 * 24 * 3600)
        XCTAssertEqual(GrokUsageService.shortWindowLabel(until: week), "7d")
    }

    func testOpenRouterRemainingIsCreditsMinusUsage() throws {
        let snapshot = try OpenRouterUsageService.parseCreditsJSON(fixture("openrouter_credits.json"))
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertEqual(snapshot.balance?.currency, "USD")
        XCTAssertEqual(snapshot.balance?.isAvailable, true)
        XCTAssertEqual(Double(snapshot.balance?.total ?? "0") ?? 0, 7.5, accuracy: 0.0001)
    }

    func testMiniMaxBuildsWindowsFromRemains() throws {
        let snapshot = try MiniMaxUsageService.parseRemainsJSON(fixture("minimax_remains.json"))
        XCTAssertGreaterThanOrEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertNil(snapshot.balance)
    }

    func testMiniMaxAccountBalanceNeverBuildsWindows() throws {
        let snapshot = try MiniMaxUsageService.parseBalanceJSON(fixture("minimax_balance.json"), currency: "USD")
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertEqual(snapshot.balance?.currency, "USD")
        XCTAssertEqual(snapshot.balance?.total, "86.50")
        XCTAssertEqual(snapshot.balance?.granted, "0")
        XCTAssertEqual(snapshot.balance?.toppedUp, "80.00")
        XCTAssertEqual(snapshot.balance?.isAvailable, true)
    }

    func testMiniMaxZeroBalanceIsUnavailable() throws {
        let snapshot = try MiniMaxUsageService.parseBalanceJSON(
            fixture("minimax_balance_unavailable.json"),
            currency: "CNY"
        )
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertEqual(snapshot.balance?.currency, "CNY")
        XCTAssertEqual(snapshot.balance?.total, "0.00")
        XCTAssertEqual(snapshot.balance?.isAvailable, false)
    }

    func testMiniMaxBalanceRejectsErrorStatus() {
        let payload = Data(#"{"base_resp":{"status_code":1004,"status_msg":"invalid api key"}}"#.utf8)
        XCTAssertThrowsError(try MiniMaxUsageService.parseBalanceJSON(payload, currency: "USD"))
    }

    func testKimiWeeklyAndRateLimitWindows() throws {
        let snapshot = try KimiUsageService.parseUsageJSON(fixture("kimi_usages.json"))
        XCTAssertEqual(snapshot.windows.map(\.label), ["7d", "5h"])
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[1].usedPercent ?? -1, 12, accuracy: 0.001)
        XCTAssertNotNil(snapshot.windows[1].resetsAt)
        XCTAssertNil(snapshot.balance)
    }

    func testKimiRejectsPayloadWithoutWindows() {
        let payload = Data(#"{"user":{"membership":{"level":"LEVEL_FREE"}}}"#.utf8)
        XCTAssertThrowsError(try KimiUsageService.parseUsageJSON(payload))
    }

    func testQoderMergesSharedCredits() throws {
        let snapshot = try QoderUsageService.parseUsageJSON(fixture("qoder_credits.json"))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].label, "Credits")
        // 1200 + 100 used over 4000 + 1000 limit.
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 26, accuracy: 0.001)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
    }

    func testMiMoBalanceFromConsolePayload() throws {
        let balance = try MiMoUsageService.parseBalanceJSON(fixture("mimo_balance.json"))
        XCTAssertEqual(balance.currency, "CNY")
        XCTAssertEqual(balance.total, "86.50")
        XCTAssertEqual(balance.granted, "6.50")
        XCTAssertEqual(balance.toppedUp, "80.00")
        XCTAssertEqual(balance.isAvailable, true)
    }

    func testMiMoLoginFailureSurfacesTokenExpired() {
        let payload = Data(#"{"code":401,"message":"login required"}"#.utf8)
        XCTAssertThrowsError(try MiMoUsageService.parseBalanceJSON(payload)) { error in
            XCTAssertEqual(error as? AIUsageError, .tokenExpired)
        }
    }

    func testMiMoTokenPlanWindowUsesPublishedPercent() throws {
        let window = MiMoUsageService.parsePlanWindow(
            detail: nil,
            usage: try fixture("mimo_token_plan_usage.json")
        )
        XCTAssertEqual(window?.label, "Credits")
        XCTAssertEqual(window?.usedPercent ?? -1, 25, accuracy: 0.001)
    }

    func testWarpUsedOverLimit() throws {
        let snapshot = try WarpUsageService.parseGraphQLJSON(fixture("warp_limit.json"))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
    }

    func testTraeCreditsClampNegativePacks() throws {
        let snapshot = try TraeUsageService.parseEntitlementJSON(fixture("trae_entitlements.json"))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].label, UsageWindowLabel.quota.key)
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 30.24, accuracy: 0.01)
        XCTAssertNil(snapshot.windows[0].resetsAt)
    }

    func testCursorSummaryUsesDashboardPercentNotCentsRatio() throws {
        let snapshot = try CursorUsageService.parseSummaryJSON(fixture("cursor_usage_summary.json"))
        XCTAssertEqual(snapshot.windows.map(\.label), [UsageWindowLabel.usage.key, "Auto"])
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 30.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[1].usedPercent ?? -1, 33.22, accuracy: 0.001)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertNil(snapshot.balance)
    }

    func testCursorCookieHeaderUsesUserIDFromJWT() throws {
        let jwt = "aaa.eyJzdWIiOiJhdXRoMHx1c2VyX2FiYyIsImV4cCI6NDEwMjQ0NDgwMH0.sig"
        let cookie = try CursorUsageService.cookieHeader(for: jwt)
        XCTAssertEqual(cookie, "WorkosCursorSessionToken=user_abc%3A%3A\(jwt)")
    }

    func testCursorDecodesUTF16LEBlob() {
        let text = "eyJhbGciOiJIUzI1NiJ9"
        var data = Data()
        for byte in text.utf8 {
            data.append(byte)
            data.append(0)
        }
        XCTAssertEqual(CursorUsageService.decodeSQLiteValue(data, type: SQLITE_BLOB), text)
    }

    func testOpenCodeGoMapsRollingWeeklyMonthly() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = try OpenCodeGoUsageService.parseUsageJSON(fixture("opencodego_usage.json"), now: now)
        XCTAssertEqual(snapshot.windows.count, 3)
        XCTAssertEqual(snapshot.windows[0].label, "5h")
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 12.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[0].resetsAt?.timeIntervalSince1970 ?? 0, 1_000_900, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[1].label, "7d")
        XCTAssertEqual(snapshot.windows[1].usedPercent ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[2].label, UsageWindowLabel.month.key)
        XCTAssertEqual(snapshot.windows[2].usedPercent ?? -1, 8.25, accuracy: 0.001)
        XCTAssertNil(snapshot.balance)
    }

    func testTraeDeviceIdIsSixteenDigitsAndStable() {
        let defaults = UserDefaults(suiteName: "LightStatsTests.trae.\(UUID().uuidString)")!
        let first = TraeUsageService.deviceId(defaults: defaults)
        let second = TraeUsageService.deviceId(defaults: defaults)
        XCTAssertEqual(first.count, 16)
        XCTAssertTrue(first.allSatisfy(\.isNumber))
        XCTAssertEqual(first, second)
    }
}
