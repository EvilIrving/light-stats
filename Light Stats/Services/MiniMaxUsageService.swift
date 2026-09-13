//
//  MiniMaxUsageService.swift
//  Light Stats
//

import Foundation

enum MiniMaxUsageService: UsageProviding {
    static var id: AIProvider { .minimax }

    private static let urls = [
        URL(string: "https://api.minimax.io/v1/api/openplatform/coding_plan/remains")!,
        URL(string: "https://api.minimax.io/v1/coding_plan/remains")!,
        URL(string: "https://www.minimax.io/v1/token_plan/remains")!,
        URL(string: "https://api.minimax.io/v1/token_plan/remains")!,
        URL(string: "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains")!
    ]

    /// Pay-as-you-go balance endpoint, same split as the official `mmx` CLI:
    /// `sk-api-` keys query the account balance; subscription keys query plan remains.
    private static let balanceURLs = [
        URL(string: "https://api.minimax.io/account/query_balance")!,
        URL(string: "https://api.minimaxi.com/account/query_balance")!
    ]

    static func fetch() async throws -> ProviderUsageSnapshot {
        let token = try await KeychainCredentialWriter.loadToken(for: .minimax)
        if token.hasPrefix("sk-api-") {
            return try await fetchAccountBalance(token: token)
        }
        return try await fetchPlanRemains(token: token)
    }

    private static func fetchAccountBalance(token: String) async throws -> ProviderUsageSnapshot {
        let headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json"
        ]
        var lastError: Error = AIUsageError.network
        for url in balanceURLs {
            do {
                let data = try await UsageHTTPClient.get(url: url, headers: headers)
                return try parseBalanceJSON(data, currency: currency(for: url))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func fetchPlanRemains(token: String) async throws -> ProviderUsageSnapshot {
        let headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        var lastError: Error = AIUsageError.network
        for url in urls {
            do {
                let data = try await UsageHTTPClient.get(url: url, headers: headers)
                return try parseRemainsJSON(data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// The balance response carries no currency field; the billing currency follows the site region.
    private static func currency(for url: URL) -> String {
        url.host?.contains("minimaxi.com") == true ? "CNY" : "USD"
    }

    static func parseBalanceJSON(_ data: Data, currency: String) throws -> ProviderUsageSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.decoding
        }
        let base = object["base_resp"] as? [String: Any]
        let status = JSONValueReader.double(base?["status_code"]) ?? 0
        guard status == 0 else { throw AIUsageError.decoding }
        guard let available = balanceAmount(object["available_amount"]), !available.isEmpty else {
            throw AIUsageError.decoding
        }
        return ProviderUsageSnapshot(
            provider: .minimax,
            windows: [],
            balance: UsageBalance(
                currency: currency,
                total: available,
                granted: balanceAmount(object["credit_balance"]),
                toppedUp: balanceAmount(object["cash_balance"]),
                isAvailable: (Double(available) ?? 0) > 0
            ),
            fetchedAt: Date()
        )
    }

    /// Amounts arrive as strings; tolerate bare numbers without inventing precision.
    private static func balanceAmount(_ value: Any?) -> String? {
        if let text = value as? String { return text.isEmpty ? nil : text }
        if let double = value as? Double { return String(format: "%.2f", double) }
        if let int = value as? Int { return String(int) }
        return nil
    }

    static func parseRemainsJSON(_ data: Data) throws -> ProviderUsageSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw AIUsageError.decoding
        }
        let root = unwrap(object)
        var windows: [UsageWindow] = []

        if let remains = array(root["model_remains"]) ?? array(root["modelRemains"]) {
            for entry in remains {
                guard let dict = entry as? [String: Any] else { continue }
                if let window = window(from: dict, fallbackLabel: string(dict["model_type"]) ?? "plan") {
                    windows.append(window)
                }
            }
        }

        if windows.isEmpty, let window = window(from: root, fallbackLabel: "plan") {
            windows.append(window)
        }

        if let weekly = dictionary(root["weekly"]) ?? dictionary(root["week"]),
           let window = window(from: weekly, fallbackLabel: "7d") {
            windows.append(window)
        }

        if windows.isEmpty { throw AIUsageError.decoding }
        return ProviderUsageSnapshot(provider: .minimax, windows: windows, fetchedAt: Date())
    }

    private static func window(from dict: [String: Any], fallbackLabel: String) -> UsageWindow? {
        let used = JSONValueReader.double(dict["used"])
            ?? JSONValueReader.double(dict["used_tokens"])
            ?? JSONValueReader.double(dict["current"])
        let total = JSONValueReader.double(dict["total"])
            ?? JSONValueReader.double(dict["total_tokens"])
            ?? JSONValueReader.double(dict["limit"])
        let remaining = JSONValueReader.double(dict["remaining"])
            ?? JSONValueReader.double(dict["remain"])
            ?? JSONValueReader.double(dict["remains"])
        let percent: Double
        if let used, let total, total > 0 {
            percent = min(100, max(0, used / total * 100))
        } else if let remaining, let total, total > 0 {
            percent = min(100, max(0, (total - remaining) / total * 100))
        } else if let published = JSONValueReader.double(dict["percentage"])
            ?? JSONValueReader.double(dict["used_percent"]) {
            percent = min(100, max(0, published))
        } else {
            return nil
        }
        let reset = JSONValueReader.date(dict["end_time"])
            ?? JSONValueReader.date(dict["reset_at"])
            ?? JSONValueReader.date(dict["remains_time"])
        let label = string(dict["interval"]) ?? fallbackLabel
        return UsageWindow(label: shortLabel(label), usedPercent: percent, resetsAt: reset)
    }

    private static func shortLabel(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("5") && (lower.contains("h") || lower.contains("hour")) { return "5h" }
        if lower.contains("week") || lower == "7d" { return "7d" }
        return String(raw.prefix(8))
    }

    private static func unwrap(_ object: Any) -> [String: Any] {
        guard let dict = object as? [String: Any] else { return [:] }
        if let data = dictionary(dict["data"]) { return data }
        if let base = dictionary(dict["base_resp"]), JSONValueReader.double(base["status_code"]) != 0 {
            return dict
        }
        return dict
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        return nil
    }
}
