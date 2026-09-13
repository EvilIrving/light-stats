//
//  DeepSeekUsageService.swift
//  Light Stats
//

import Foundation

enum DeepSeekUsageService: UsageProviding {
    static var id: AIProvider { .deepseek }

    private static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    static func fetch() async throws -> ProviderUsageSnapshot {
        let token = try await KeychainCredentialWriter.loadToken(for: .deepseek)
        let data = try await UsageHTTPClient.get(
            url: balanceURL,
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json"
            ]
        )
        return try parseBalanceJSON(data)
    }

    static func parseBalanceJSON(_ data: Data) throws -> ProviderUsageSnapshot {
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: data)
        } catch {
            throw AIUsageError.decoding
        }
        guard let chosen = pickBalance(root.balanceInfos) else {
            throw AIUsageError.decoding
        }
        return ProviderUsageSnapshot(
            provider: .deepseek,
            windows: [],
            balance: UsageBalance(
                currency: chosen.currency,
                total: chosen.totalBalance,
                granted: chosen.grantedBalance,
                toppedUp: chosen.toppedUpBalance,
                isAvailable: root.isAvailable ?? true
            ),
            fetchedAt: Date()
        )
    }

    private static func pickBalance(_ infos: [BalanceInfo]) -> BalanceInfo? {
        guard !infos.isEmpty else { return nil }
        let positive = infos.filter { Double($0.totalBalance) ?? 0 > 0 }
        if let cny = positive.first(where: { $0.currency.uppercased() == "CNY" }) {
            return cny
        }
        if let firstPositive = positive.first {
            return firstPositive
        }
        if let cny = infos.first(where: { $0.currency.uppercased() == "CNY" }) {
            return cny
        }
        return infos.first
    }

    private struct Root: Decodable {
        let isAvailable: Bool?
        let balanceInfos: [BalanceInfo]

        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    private struct BalanceInfo: Decodable {
        let currency: String
        let totalBalance: String
        let grantedBalance: String?
        let toppedUpBalance: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }
}
