//
//  AIUsageProviderRow.swift
//  Light Stats
//

import Foundation

struct AIUsageProviderRow: Identifiable, Equatable, Sendable {
    let id: AIProvider
    let displayName: String
    let displayNameKey: String
    let iconAssetName: String
    let symbolFallback: String
    let cliName: String?
    let credential: CredentialSource
    let supportsWarmup: Bool
    let showsBalance: Bool
    let tokenHintKey: String?
}
