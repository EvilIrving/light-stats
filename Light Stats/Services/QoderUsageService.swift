//
//  QoderUsageService.swift
//  Light Stats
//

import Foundation

/// Qoder big-model credit usage, read from the account dashboard API the web console
/// itself calls. Authentication is the browser session cookie, so no OAuth flow is needed.
enum QoderUsageService: UsageProviding {
    static var id: AIProvider { .qoder }

    private struct Site {
        let usage: URL
        let origin: String
        let referer: String
    }

    private static let sites = [
        Site(
            usage: URL(string: "https://qoder.com/api/v2/me/usages/big_model_credits")!,
            origin: "https://qoder.com",
            referer: "https://qoder.com/account/usage"
        ),
        Site(
            usage: URL(string: "https://qoder.com.cn/api/v2/me/usages/big_model_credits")!,
            origin: "https://qoder.com.cn",
            referer: "https://qoder.com.cn/account/usage"
        )
    ]

    static func fetch() async throws -> ProviderUsageSnapshot {
        let cookie = try await KeychainCredentialWriter.loadToken(for: .qoder)
        var lastError: Error = AIUsageError.network
        for site in sites {
            do {
                let data = try await UsageHTTPClient.get(
                    url: site.usage,
                    headers: [
                        "Cookie": cookie,
                        "Origin": site.origin,
                        "Referer": site.referer,
                        "Accept": "application/json"
                    ]
                )
                return try parseUsageJSON(data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Shape: `{ totalQuota: { quotaSummary: { used_value, limit_value, usage_percentage, unit } },
    /// sharedQuota: {...}, next_reset_at }`. The shared pool is added to the plan pool.
    static func parseUsageJSON(_ data: Data) throws -> ProviderUsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.decoding
        }
        let total = summary(root["totalQuota"] ?? root["total_quota"])
        let shared = summary(root["sharedQuota"] ?? root["shared_quota"])
        guard total != nil || shared != nil else { throw AIUsageError.decoding }

        let used = (total?.used ?? 0) + (shared?.used ?? 0)
        let limit = (total?.limit ?? 0) + (shared?.limit ?? 0)
        let percent: Double
        if limit > 0 {
            percent = min(100, max(0, used / limit * 100))
        } else {
            percent = min(100, max(0, total?.percent ?? shared?.percent ?? 0))
        }
        let label = total?.unit.flatMap { $0.isEmpty ? nil : $0 } ?? "Credits"
        let window = UsageWindow(
            label: String(label.prefix(8)),
            usedPercent: percent,
            resetsAt: JSONValueReader.date(root["nextResetAt"] ?? root["next_reset_at"])
        )
        return ProviderUsageSnapshot(provider: .qoder, windows: [window], fetchedAt: Date())
    }

    private static func summary(_ value: Any?) -> (used: Double, limit: Double, percent: Double?, unit: String?)? {
        guard let container = value as? [String: Any],
              let quota = (container["quotaSummary"] ?? container["quota_summary"]) as? [String: Any] else {
            return nil
        }
        let used = JSONValueReader.double(quota["used_value"] ?? quota["usedValue"]) ?? 0
        let limit = JSONValueReader.double(quota["limit_value"] ?? quota["limitValue"]) ?? 0
        let percent = JSONValueReader.double(quota["usage_percentage"] ?? quota["usagePercentage"])
        return (used, limit, percent, quota["unit"] as? String)
    }
}
