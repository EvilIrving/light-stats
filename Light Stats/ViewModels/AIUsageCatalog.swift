//
//  AIUsageCatalog.swift
//  Light Stats
//

import Foundation

@MainActor
enum AIUsageCatalog {
    /// Recomputed every access so `displayNameKey.localized` follows language changes.
    static var providers: [AIUsageProviderRow] {
        UsageProviderRegistry.all.map(row(from:))
    }

    static func row(for id: AIProvider) -> AIUsageProviderRow? {
        providers.first { $0.id == id }
    }

    private static func row(from desc: UsageProviderDescriptor) -> AIUsageProviderRow {
        AIUsageProviderRow(
            id: desc.id,
            displayName: desc.displayNameKey.localized,
            displayNameKey: desc.displayNameKey,
            iconAssetName: desc.iconAssetName,
            symbolFallback: desc.symbolFallback,
            cliName: desc.cliName,
            credential: desc.credential,
            supportsWarmup: desc.supportsWarmup,
            showsBalance: desc.showsBalance,
            tokenHintKey: desc.tokenHintKey
        )
    }
}
