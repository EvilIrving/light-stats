//
//  ClaudeUsageService.swift
//  Light Stats
//
//  Created on 2026/06/10.
//

import Foundation
import Security

/// Fetches Claude Code subscription usage via the OAuth usage endpoint.
/// Credentials are maintained by the Claude Code CLI; we only read them.
enum ClaudeUsageService {

    private static let keychainService = "Claude Code-credentials"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    // MARK: - Response models (all optional: undocumented API, tolerate changes)

    private struct UsageResponse: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }

        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?

            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }
        }
    }

    // MARK: - Fetch

    static func fetch() async throws -> ProviderUsageSnapshot {
        guard let token = readAccessToken() else {
            throw AIUsageError.credentialsMissing
        }

        var request = URLRequest(url: usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIUsageError.network
        }

        guard let http = response as? HTTPURLResponse else { throw AIUsageError.network }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AIUsageError.tokenExpired
        }
        guard (200..<300).contains(http.statusCode) else { throw AIUsageError.network }

        guard let decoded = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            throw AIUsageError.decoding
        }

        let isoParser = ISO8601DateFormatter()
        isoParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoParserNoFraction = ISO8601DateFormatter()

        func parseDate(_ string: String?) -> Date? {
            guard let string else { return nil }
            return isoParser.date(from: string) ?? isoParserNoFraction.date(from: string)
        }

        var windows: [UsageWindow] = []
        if let w = decoded.fiveHour, let used = w.utilization {
            windows.append(UsageWindow(label: "5h", usedPercent: used, resetsAt: parseDate(w.resetsAt)))
        }
        if let w = decoded.sevenDay, let used = w.utilization {
            windows.append(UsageWindow(label: "7d", usedPercent: used, resetsAt: parseDate(w.resetsAt)))
        }

        guard !windows.isEmpty else { throw AIUsageError.decoding }

        return ProviderUsageSnapshot(provider: .claude, windows: windows, fetchedAt: Date())
    }

    // MARK: - Keychain

    /// In-memory cache of the OAuth access token so we only hit the Keychain
    /// once per process lifetime. Keychain access to another app's item
    /// triggers a macOS authorization prompt; caching avoids repeated prompts.
    private static var _cachedToken: String?
    private static var _tokenFailed: Bool = false

    /// Reads the OAuth access token from the Claude Code CLI keychain item.
    /// First access triggers a one-time keychain authorization prompt;
    /// subsequent calls return the in-memory copy.
    private static func readAccessToken() -> String? {
        if let token = _cachedToken {
            return token
        }
        if _tokenFailed {
            return nil
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            _tokenFailed = true
            return nil
        }
        _cachedToken = token
        return token
    }
}
