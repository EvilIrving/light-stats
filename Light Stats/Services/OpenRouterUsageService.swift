//
//  OpenRouterUsageService.swift
//  Light Stats
//

import Foundation

enum OpenRouterUsageService: UsageProviding {
    static var id: AIProvider { .openrouter }

    private static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!

    static func fetch() async throws -> ProviderUsageSnapshot {
        let token = try await KeychainCredentialWriter.loadToken(for: .openrouter)
        let data = try await UsageHTTPClient.get(
            url: creditsURL,
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json"
            ]
        )
        return try parseCreditsJSON(data)
    }

    static func parseCreditsJSON(_ data: Data) throws -> ProviderUsageSnapshot {
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: data)
        } catch {
            throw AIUsageError.decoding
        }
        guard let payload = root.data else { throw AIUsageError.decoding }
        let remaining = payload.totalCredits - payload.totalUsage
        let total = String(format: "%.4f", remaining)
        return ProviderUsageSnapshot(
            provider: .openrouter,
            windows: [],
            balance: UsageBalance(
                currency: "USD",
                total: total,
                granted: nil,
                toppedUp: String(format: "%.4f", payload.totalCredits),
                isAvailable: remaining > 0
            ),
            fetchedAt: Date()
        )
    }

    private struct Root: Decodable {
        let data: Payload?
    }

    private struct Payload: Decodable {
        let totalCredits: Double
        let totalUsage: Double

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
}
