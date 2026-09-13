//
//  MiMoUsageService.swift
//  Light Stats
//

import Foundation

/// Xiaomi MiMo console balance plus Token Plan credits. The console API authenticates
/// with the browser session cookie (`api-platform_serviceToken` + `userId`), so the
/// stored credential is a `Cookie:` header rather than an API key.
enum MiMoUsageService: UsageProviding {
    static var id: AIProvider { .mimo }

    private static let baseURL = URL(string: "https://platform.xiaomimimo.com/api/v1")!

    static func fetch() async throws -> ProviderUsageSnapshot {
        let cookie = try await KeychainCredentialWriter.loadToken(for: .mimo)
        let balanceData = try await get("balance", cookie: cookie)
        let balance = try parseBalanceJSON(balanceData)

        let detail = try? await get("tokenPlan/detail", cookie: cookie)
        let usage = try? await get("tokenPlan/usage", cookie: cookie)
        let plan = parsePlanWindow(detail: detail, usage: usage)

        return ProviderUsageSnapshot(
            provider: .mimo,
            windows: plan.map { [$0] } ?? [],
            balance: balance,
            fetchedAt: Date()
        )
    }

    private static func get(_ path: String, cookie: String) async throws -> Data {
        try await UsageHTTPClient.get(
            url: baseURL.appendingPathComponent(path),
            headers: [
                "Cookie": cookie,
                "Accept": "application/json, text/plain, */*",
                "Origin": "https://platform.xiaomimimo.com",
                "Referer": "https://platform.xiaomimimo.com/#/console/balance"
            ]
        )
    }

    /// Shape: `{ code: 0, message, data: { balance, cash_balance, gift_balance, currency } }`.
    /// Amounts are strings; `code` doubles as the login-failure signal.
    static func parseBalanceJSON(_ data: Data) throws -> UsageBalance {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.decoding
        }
        if let code = JSONValueReader.double(root["code"]), code != 0 {
            switch Int(code) {
            case 401: throw AIUsageError.tokenExpired
            case 403: throw AIUsageError.credentialsMissing
            default: throw AIUsageError.decoding
            }
        }
        guard let payload = root["data"] as? [String: Any],
              let total = text(payload["balance"]) else {
            throw AIUsageError.decoding
        }
        let currency = text(payload["currency"]) ?? "CNY"
        return UsageBalance(
            currency: currency,
            total: total,
            granted: text(payload["gift_balance"] ?? payload["giftBalance"]),
            toppedUp: text(payload["cash_balance"] ?? payload["cashBalance"]),
            isAvailable: (Double(total) ?? 0) > 0
        )
    }

    /// Token Plan payloads are lightly documented, so keys are matched tolerantly and a
    /// missing or empty plan simply yields no window instead of failing the balance read.
    static func parsePlanWindow(detail: Data?, usage: Data?) -> UsageWindow? {
        let detailRoot = detail.flatMap(dictionary(from:))
        let usageRoot = usage.flatMap(dictionary(from:))
        guard let payload = usageRoot else { return nil }

        let used = JSONValueReader.double(firstValue(payload, matching: ["used", "used_tokens", "usage", "usedTokens"]))
        let limit = JSONValueReader.double(firstValue(payload, matching: ["limit", "total", "total_tokens", "quota", "token_limit"]))
        let published = JSONValueReader.double(firstValue(payload, matching: ["percent", "percentage", "used_percent", "usedPercent"]))
        let percent: Double
        if let used, let limit, limit > 0 {
            percent = min(100, max(0, used / limit * 100))
        } else if let published {
            percent = min(100, max(0, published <= 1 ? published * 100 : published))
        } else {
            return nil
        }

        let periodEnd = detailRoot.flatMap {
            JSONValueReader.date(firstValue($0, matching: ["period_end", "periodEnd", "expire_time", "expireTime"]))
        }
        return UsageWindow(label: "Credits", usedPercent: percent, resetsAt: periodEnd)
    }

    private static func dictionary(from data: Data) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["data"] as? [String: Any]) ?? object
    }

    private static func firstValue(_ dict: [String: Any], matching keys: [String]) -> Any? {
        for key in keys where dict[key] != nil { return dict[key] }
        let lowered = keys.map { $0.lowercased() }
        for (key, value) in dict where lowered.contains(key.lowercased()) { return value }
        return nil
    }

    private static func text(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let double = value as? Double { return String(format: "%.2f", double) }
        if let int = value as? Int { return String(int) }
        return nil
    }
}
