//
//  OpenCodeGoUsageService.swift
//  Light Stats
//

import Foundation

enum OpenCodeGoUsageService: UsageProviding {
    static var id: AIProvider { .opencodego }

    private static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    static func fetch() async throws -> ProviderUsageSnapshot {
        let token = try await KeychainCredentialWriter.loadToken(for: .opencodego)
        let data = try await UsageHTTPClient.get(
            url: usageURL,
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json"
            ]
        )
        return try parseUsageJSON(data)
    }

    static func parseUsageJSON(_ data: Data, now: Date = Date()) throws -> ProviderUsageSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.decoding
        }
        let usage = dictionary(object["usage"]) ?? object
        guard let rolling = dictionary(usage["rolling"]) ?? dictionary(object["rolling"]),
              let rollingWindow = window(from: rolling, label: "5h", now: now) else {
            throw AIUsageError.decoding
        }
        var windows = [rollingWindow]
        if let weekly = dictionary(usage["weekly"]) ?? dictionary(object["weekly"]),
           let weeklyWindow = window(from: weekly, label: "7d", now: now) {
            windows.append(weeklyWindow)
        }
        if let monthly = dictionary(usage["monthly"]) ?? dictionary(object["monthly"]),
           let monthlyWindow = window(from: monthly, label: UsageWindowLabel.month.key, now: now) {
            windows.append(monthlyWindow)
        }
        return ProviderUsageSnapshot(provider: .opencodego, windows: windows, fetchedAt: now)
    }

    private static func window(from dict: [String: Any], label: String, now: Date) -> UsageWindow? {
        guard let percent = percent(from: dict) else { return nil }
        return UsageWindow(
            label: label,
            usedPercent: min(100, max(0, percent)),
            resetsAt: resetDate(from: dict, now: now)
        )
    }

    private static func percent(from dict: [String: Any]) -> Double? {
        let keys = ["percent", "usagePercent", "usedPercent", "percentUsed", "usage_percent", "used_percent"]
        for key in keys {
            if let value = JSONValueReader.double(dict[key]) { return value }
        }
        let used = JSONValueReader.double(dict["used"]) ?? JSONValueReader.double(dict["consumed"])
        let limit = JSONValueReader.double(dict["limit"]) ?? JSONValueReader.double(dict["total"]) ?? JSONValueReader.double(dict["quota"])
        if let used, let limit, limit > 0 {
            return used / limit * 100
        }
        return nil
    }

    private static func resetDate(from dict: [String: Any], now: Date) -> Date? {
        let resetInKeys = ["resetInSec", "resetInSeconds", "reset_in_sec", "resetsInSec", "resetSeconds"]
        for key in resetInKeys {
            if let seconds = JSONValueReader.double(dict[key]) {
                return now.addingTimeInterval(seconds)
            }
        }
        let resetAtKeys = ["resetAt", "resetsAt", "reset_at", "resets_at", "nextReset", "renewAt"]
        for key in resetAtKeys {
            if let date = JSONValueReader.date(dict[key]) { return date }
        }
        return nil
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }
}
