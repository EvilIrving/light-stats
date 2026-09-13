//
//  UsageProviderDescriptor.swift
//  Light Stats
//

import Foundation

/// Closed descriptor for one provider. Fetch/reset are closures so Swift 5.9
/// can call them through the registry without `any UsageProviding.Type`.
struct UsageProviderDescriptor: Sendable, Identifiable {
    let id: AIProvider
    let credential: CredentialSource
    let displayNameKey: String
    let iconAssetName: String
    let symbolFallback: String
    let cliName: String?
    let supportsWarmup: Bool
    /// Reports a prepaid balance that renders as a grid cell below the usage rows.
    let showsBalance: Bool
    /// Localized prompt shown in the token field; nil for the plain API-token case.
    let tokenHintKey: String?
    let fetch: @Sendable () async throws -> ProviderUsageSnapshot
    let resetCredentialCache: @Sendable () -> Void
}
