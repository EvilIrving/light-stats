//
//  ZAIUsageService.swift
//  Light Stats
//

import Foundation

enum ZAIUsageService: UsageProviding {
    static var id: AIProvider { .zai }

    private static let intlURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
    private static let cnURL = URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
    private static let accountURL = URL(string: "https://www.bigmodel.cn/api/biz/account/query-customer-account-report")!

    static func fetch() async throws -> ProviderUsageSnapshot {
        let token = try await resolvedToken()
        let headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json"
        ]
        for url in [intlURL, cnURL] {
            do {
                let data = try await UsageHTTPClient.get(url: url, headers: headers)
                return try parseQuotaJSON(data)
            } catch AIUsageError.network, AIUsageError.endpointNotFound, AIUsageError.decoding,
                    AIUsageError.tokenExpired {
                continue
            }
        }
        let data = try await UsageHTTPClient.get(url: accountURL, headers: headers)
        return try parseAccountJSON(data)
    }

    static func parseQuotaJSON(_ data: Data) throws -> ProviderUsageSnapshot {
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: data)
        } catch {
            throw AIUsageError.decoding
        }
        guard root.success == true || root.code == 200,
              let limits = root.data?.limits else {
            throw AIUsageError.decoding
        }

        var windows: [UsageWindow] = []
        var balance: UsageBalance?
        for limit in limits {
            if let percent = numericPercent(limit.percentage) {
                windows.append(UsageWindow(
                    label: windowLabel(limit),
                    usedPercent: min(100, max(0, percent)),
                    resetsAt: resetDate(limit.nextResetTime)
                ))
                continue
            }
            if let currency = limit.currency, !currency.isEmpty,
               let amount = firstAmount(limit) {
                if balance == nil {
                    balance = UsageBalance(
                        currency: currency,
                        total: amount,
                        granted: nil,
                        toppedUp: nil,
                        isAvailable: true
                    )
                }
            }
        }
        if windows.isEmpty && balance == nil {
            throw AIUsageError.decoding
        }
        return ProviderUsageSnapshot(
            provider: .zai,
            windows: windows,
            balance: balance,
            fetchedAt: Date()
        )
    }

    static func parseAccountJSON(_ data: Data) throws -> ProviderUsageSnapshot {
        let root: AccountRoot
        do {
            root = try JSONDecoder().decode(AccountRoot.self, from: data)
        } catch {
            throw AIUsageError.decoding
        }
        guard root.success == true || root.code == 200, let payload = root.data else {
            throw AIUsageError.decoding
        }
        let available = payload.availableBalance ?? payload.balance
        guard let available else { throw AIUsageError.decoding }
        return ProviderUsageSnapshot(
            provider: .zai,
            windows: [],
            balance: UsageBalance(
                currency: "CNY",
                total: money(available),
                granted: payload.giveAmount.map(money),
                toppedUp: payload.rechargeAmount.map(money),
                isAvailable: available > 0
            ),
            fetchedAt: Date()
        )
    }

    private static func resolvedToken() async throws -> String {
        if let pasted = try? await KeychainCredentialWriter.loadToken(for: .zai) {
            return pasted
        }
        if let fromClaude = await Task.detached(operation: { claudeRelayToken() }).value {
            return fromClaude
        }
        throw AIUsageError.credentialsMissing
    }

    nonisolated private static func claudeRelayToken() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return claudeRelayToken(from: json)
    }

    nonisolated static func claudeRelayToken(from json: [String: Any]) -> String? {
        if let env = json["env"] as? [String: Any],
           let baseURL = env["ANTHROPIC_BASE_URL"] as? String,
           let url = URL(string: baseURL),
           url.scheme?.lowercased() == "https",
           let host = url.host?.lowercased(),
           ["api.z.ai", "open.bigmodel.cn"].contains(host),
           let token = env["ANTHROPIC_AUTH_TOKEN"] as? String,
           !token.isEmpty {
            return token
        }
        return nil
    }

    private static func numericPercent(_ value: FlexibleNumber?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .double(let number):
            return number.isFinite ? number : nil
        case .int(let number):
            return Double(number)
        }
    }

    private static func firstAmount(_ limit: Limit) -> String? {
        if let total = stringify(limit.total) { return total }
        if let amount = stringify(limit.amount) { return amount }
        if let remaining = stringify(limit.remaining) { return remaining }
        if let balance = stringify(limit.balance) { return balance }
        return nil
    }

    private static func stringify(_ value: FlexibleNumber?) -> String? {
        guard let value else { return nil }
        switch value {
        case .double(let number):
            return String(number)
        case .int(let number):
            return String(number)
        }
    }

    private static func windowLabel(_ limit: Limit) -> String {
        let minutes = windowMinutes(unit: limit.unit, number: limit.number)
        if minutes == 300 { return "5h" }
        if minutes == 10080 { return "7d" }
        switch limit.type {
        case "TIME_LIMIT": return "MCP"
        case "CREDIT_LIMIT": return UsageWindowLabel.quota.key
        default: return UsageWindowLabel.quota.key
        }
    }

    private static func windowMinutes(unit: Int?, number: Int?) -> Int? {
        guard let unit, let number, number > 0 else { return nil }
        switch unit {
        case 1: return number * 1440
        case 3: return number * 60
        case 5: return number
        case 6: return number * 10080
        default: return nil
        }
    }

    private static func resetDate(_ millis: Int64?) -> Date? {
        guard let millis, millis > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    private static func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private struct AccountRoot: Decodable {
        let success: Bool?
        let code: Int?
        let data: AccountData?
    }

    private struct AccountData: Decodable {
        let availableBalance: Double?
        let balance: Double?
        let giveAmount: Double?
        let rechargeAmount: Double?
    }

    private struct Root: Decodable {
        let success: Bool?
        let code: Int?
        let data: DataBlock?
    }

    private struct DataBlock: Decodable {
        let limits: [Limit]?
    }

    private struct Limit: Decodable {
        let type: String?
        let unit: Int?
        let number: Int?
        let percentage: FlexibleNumber?
        let nextResetTime: Int64?
        let currency: String?
        let total: FlexibleNumber?
        let amount: FlexibleNumber?
        let remaining: FlexibleNumber?
        let balance: FlexibleNumber?
    }

    private enum FlexibleNumber: Decodable {
        case int(Int)
        case double(Double)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let int = try? container.decode(Int.self) {
                self = .int(int)
            } else if let double = try? container.decode(Double.self) {
                self = .double(double)
            } else if let string = try? container.decode(String.self),
                      let double = Double(string) {
                self = .double(double)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a number")
            }
        }
    }
}
