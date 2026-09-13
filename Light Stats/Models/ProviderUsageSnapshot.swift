//
//  ProviderUsageSnapshot.swift
//  Light Stats
//

import Foundation

/// One successful fetch result for a provider.
struct ProviderUsageSnapshot: Codable, Equatable, Sendable {
    let provider: AIProvider
    let windows: [UsageWindow]
    let balance: UsageBalance?
    let fetchedAt: Date

    init(
        provider: AIProvider,
        windows: [UsageWindow],
        balance: UsageBalance? = nil,
        fetchedAt: Date
    ) {
        self.provider = provider
        self.windows = windows
        self.balance = balance
        self.fetchedAt = fetchedAt
    }
}
