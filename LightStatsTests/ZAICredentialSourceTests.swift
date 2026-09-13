import XCTest
@testable import Light_Stats

final class ZAICredentialSourceTests: XCTestCase {
    func testAcceptsOnlyKnownHTTPSRelayHosts() {
        for baseURL in ["https://api.z.ai/api/anthropic", "https://open.bigmodel.cn/api/anthropic"] {
            XCTAssertEqual(token(baseURL: baseURL), "test-token")
        }
    }

    func testRejectsUnrelatedOrSpoofedRelayHosts() {
        for baseURL in [
            "https://relay.example/api/anthropic",
            "https://api.z.ai.example/api/anthropic",
            "https://api.z.ai@relay.example/api/anthropic",
            "http://api.z.ai/api/anthropic",
            "invalid"
        ] {
            XCTAssertNil(token(baseURL: baseURL))
        }
        XCTAssertNil(ZAIUsageService.claudeRelayToken(from: [
            "env": ["ANTHROPIC_AUTH_TOKEN": "test-token"]
        ]))
    }

    private func token(baseURL: String) -> String? {
        ZAIUsageService.claudeRelayToken(from: [
            "env": ["ANTHROPIC_BASE_URL": baseURL, "ANTHROPIC_AUTH_TOKEN": "test-token"]
        ])
    }
}
