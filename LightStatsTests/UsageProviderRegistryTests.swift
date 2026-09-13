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
}
