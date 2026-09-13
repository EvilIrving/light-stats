//
//  KimiUsageService.swift
//  Light Stats
//

import Foundation

/// Kimi For Coding subscription quotas (the `api.kimi.com/coding` platform):
/// a weekly quota plus 5-hour rate-limit windows. This is deliberately separate
/// from the Moonshot pay-as-you-go balance, which a different account surface bills.
enum KimiUsageService: UsageProviding {
    static var id: AIProvider { .kimi }

    private static let usageURL = URL(string: "https://api.kimi.com/coding/v1/usages")!

    static func fetch() async throws -> ProviderUsageSnapshot {
        let token = try await KeychainCredentialWriter.loadToken(for: .kimi)
        let data = try await UsageHTTPClient.get(
            url: usageURL,
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json"
            ]
        )
        return try parseUsageJSON(data)
    }

    /// Shape: `{ usage: {...}, limits: [{ window, detail: {...} }], user: { membership: { level } } }`.
    /// Counts arrive as strings, so every amount goes through `JSONValueReader.double(_:)`.
    static func parseUsageJSON(_ data: Data) throws -> ProviderUsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.decoding
        }
        var windows: [UsageWindow] = []
        if let weekly = window(from: root["usage"], label: "7d") {
            windows.append(weekly)
        }
        if let limits = root["limits"] as? [[String: Any]] {
            for limit in limits {
                let label = shortLabel(limit["window"]) ?? UsageWindowLabel.quota.key
                if let rateLimit = window(from: limit["detail"], label: label) {
                    windows.append(rateLimit)
                }
            }
        }
        if windows.isEmpty { throw AIUsageError.decoding }
        return ProviderUsageSnapshot(provider: .kimi, windows: windows, fetchedAt: Date())
    }

    private static func window(from value: Any?, label: String) -> UsageWindow? {
        guard let dict = value as? [String: Any] else { return nil }
        let limit = JSONValueReader.double(dict["limit"])
        let used = JSONValueReader.double(dict["used"])
        let remaining = JSONValueReader.double(dict["remaining"])
        let percent: Double
        if let used, let limit, limit > 0 {
            percent = min(100, max(0, used / limit * 100))
        } else if let remaining, let limit, limit > 0 {
            percent = min(100, max(0, (limit - remaining) / limit * 100))
        } else {
            return nil
        }
        let reset = JSONValueReader.date(dict["resetTime"] ?? dict["reset_time"] ?? dict["resetAt"] ?? dict["reset_at"])
        return UsageWindow(label: label, usedPercent: percent, resetsAt: reset)
    }

    /// Windows arrive either as a duration in seconds or as an already-short label.
    private static func shortLabel(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty {
            if let seconds = Double(text) { return shortLabel(seconds: seconds) }
            return String(text.prefix(8))
        }
        if let seconds = value as? Double { return shortLabel(seconds: seconds) }
        if let seconds = value as? Int { return shortLabel(seconds: Double(seconds)) }
        return nil
    }

    private static func shortLabel(seconds: Double) -> String? {
        guard seconds > 0 else { return nil }
        if seconds <= 6 * 3600 { return "5h" }
        if seconds <= 8 * 86400 { return "7d" }
        return "\(Int(seconds / 86400))d"
    }
}
