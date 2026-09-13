//
//  UsageProviderRegistryTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

final class UsageProviderRegistryTests: XCTestCase {
    func testRegistryCoversEveryAIProvider() {
        XCTAssertEqual(
            Set(UsageProviderRegistry.all.map(\.id)),
            Set(AIProvider.allCases)
        )
        XCTAssertEqual(
            UsageProviderRegistry.all.map(\.id),
            Array(AIProvider.allCases)
        )
        for (descriptor, id) in zip(UsageProviderRegistry.all, AIProvider.allCases) {
            XCTAssertEqual(descriptor.id, id)
        }
    }

    func testResetCredentialCacheThroughRegistryCompiles() {
        UsageProviderRegistry.resetCredentialCache(.claude)
    }

    func testBalanceProvidersAreGroupedAtEnd() {
        let flags = UsageProviderRegistry.all.map(\.showsBalance)
        guard let firstBalance = flags.firstIndex(of: true) else {
            XCTFail("expected at least one balance provider")
            return
        }
        XCTAssertFalse(flags[..<firstBalance].contains(true))
        XCTAssertTrue(flags[firstBalance...].allSatisfy { $0 })
        XCTAssertEqual(
            UsageProviderRegistry.all.filter(\.showsBalance).map(\.id),
            [.deepseek, .zai, .minimax, .openrouter, .mimo]
        )
    }
}
