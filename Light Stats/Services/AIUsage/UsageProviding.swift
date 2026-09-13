//
//  UsageProviding.swift
//  Light Stats
//

import Foundation

/// Compile-time usage provider. Existing services are stateless enums; do not instantiate them.
protocol UsageProviding: Sendable {
    static var id: AIProvider { get }
    static func fetch() async throws -> ProviderUsageSnapshot
    static func resetCredentialCache()
}

extension UsageProviding {
    static func resetCredentialCache() {}
}
