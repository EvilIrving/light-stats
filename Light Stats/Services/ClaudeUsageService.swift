//
//  ClaudeUsageService.swift
//  Light Stats
//
//  Created on 2026/06/10.
//

import Foundation
import Security

/// Fetches Claude Code subscription usage.
/// Credentials are maintained by the Claude Code CLI; we only read them.
///
/// Primary data source: OAuth usage endpoint.
/// Fallback: when that endpoint returns 404, parse rate-limit headers from a
/// minimal Messages API call (Haiku, 1 token — negligible cost).
///
/// Credential sources (tried in order, zero prompts for most users):
/// 1. `~/.claude/.credentials.json` (file I/O, no authorization prompt)
/// 2. `~/.claude/credentials.json` (legacy path)
/// 3. Keychain `Claude Code-credentials` (last resort – one-time macOS auth dialog)
///
/// API contracts (all undocumented — decode defensively):
///
/// OAuth usage:
/// - Request:  `GET https://api.anthropic.com/api/oauth/usage`
/// - Headers:  `Authorization: Bearer <accessToken>`
///             `anthropic-beta: oauth-2025-04-20`
/// - Response: `{ "five_hour": { utilization: 0–100, resets_at: ISO8601 }, … }`
///
/// Messages API fallback:
/// - Request:  `POST https://api.anthropic.com/v1/messages` (1-token Haiku)
/// - Headers:  `Authorization: Bearer <accessToken>`
///             `anthropic-version: 2023-06-01`
/// - Reads:    `anthropic-ratelimit-unified-5h-utilization` (0.0–1.0)
///             `anthropic-ratelimit-unified-7d-utilization`
///             `anthropic-ratelimit-unified-5h-reset` (Unix epoch)
///             `anthropic-ratelimit-unified-7d-reset`
/// - Errors:   401/403 → token expired. All fields optional.
enum ClaudeUsageService {

    private static let keychainService = "Claude Code-credentials"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Paths for on-disk credential files (read when Keychain is unavailable/truncated).
    private static var credentialFileURLs: [URL] {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        return [
            claudeDir.appendingPathComponent(".credentials.json"),
            claudeDir.appendingPathComponent("credentials.json")
        ]
    }

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

        // 1. Try the OAuth usage endpoint.
        let oauthResult = await fetchOAuthUsage(token: token)

        // 2. If the endpoint moved or the response shape changed, fall back to Messages API headers.
        if case .failure(let error) = oauthResult {
            switch error {
            case .tokenExpired, .credentialsMissing:
                throw error
            case .endpointNotFound, .decoding:
                return try await fetchUsageFromHeaders(token: token)
            case .network:
                throw error
            }
        }

        return try oauthResult.get()
    }

    // MARK: - OAuth usage endpoint

    private static func fetchOAuthUsage(token: String) async -> Result<ProviderUsageSnapshot, AIUsageError> {
        var request = URLRequest(url: usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await URLSession.shared.data(for: request)
            data = d
            guard let h = response as? HTTPURLResponse else { return .failure(.network) }
            http = h
        } catch {
            return .failure(.network)
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            return .failure(.tokenExpired)
        }
        if http.statusCode == 404 {
            return .failure(.endpointNotFound)
        }
        guard (200..<300).contains(http.statusCode) else { return .failure(.network) }

        guard let decoded = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            return .failure(.decoding)
        }

        let windows = parseWindows(from: decoded)
        guard !windows.isEmpty else { return .failure(.decoding) }

        return .success(ProviderUsageSnapshot(provider: .claude, windows: windows, fetchedAt: Date()))
    }

    // MARK: - Messages API fallback (rate-limit headers)

    /// Sends a minimal Messages API request (Haiku, 1 output token) solely to
    /// read rate-limit response headers. Token cost is negligible (~10 input +
    /// 1 output token). Only called when the OAuth usage endpoint is unavailable.
    private static func fetchUsageFromHeaders(token: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: messagesURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIUsageError.network
        }

        guard let http = response as? HTTPURLResponse else { throw AIUsageError.network }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AIUsageError.tokenExpired
        }
        guard http.statusCode == 200 else { throw AIUsageError.network }

        return try parseRateLimitHeaders(from: http)
    }

    /// Parses Anthropic rate-limit response headers into usage windows.
    /// Header values are 0.0–1.0 utilization; reset timestamps are Unix epoch seconds.
    private static func parseRateLimitHeaders(from response: HTTPURLResponse) throws -> ProviderUsageSnapshot {
        func headerDouble(_ name: String) -> Double? {
            guard let value = response.value(forHTTPHeaderField: name) else { return nil }
            return Double(value)
        }

        func headerTimestamp(_ name: String) -> Date? {
            guard let ts = headerDouble(name), ts > 0 else { return nil }
            return Date(timeIntervalSince1970: ts)
        }

        var windows: [UsageWindow] = []

        if let util = headerDouble("anthropic-ratelimit-unified-5h-utilization") {
            let resetAt = headerTimestamp("anthropic-ratelimit-unified-5h-reset")
            // Ignore a window whose reset is already in the past.
            if resetAt == nil || (resetAt ?? Date.distantPast) > Date() {
                windows.append(UsageWindow(label: "5h", usedPercent: min(100, util * 100), resetsAt: resetAt))
            }
        }

        if let util = headerDouble("anthropic-ratelimit-unified-7d-utilization") {
            let resetAt = headerTimestamp("anthropic-ratelimit-unified-7d-reset")
            windows.append(UsageWindow(label: "7d", usedPercent: min(100, util * 100), resetsAt: resetAt))
        }

        guard !windows.isEmpty else { throw AIUsageError.decoding }

        return ProviderUsageSnapshot(provider: .claude, windows: windows, fetchedAt: Date())
    }

    // MARK: - Response parsing

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserNoFraction = ISO8601DateFormatter()

    private static func parseWindows(from response: UsageResponse) -> [UsageWindow] {
        func parseDate(_ string: String?) -> Date? {
            guard let string else { return nil }
            return isoParser.date(from: string) ?? isoParserNoFraction.date(from: string)
        }

        var windows: [UsageWindow] = []
        if let w = response.fiveHour, let used = w.utilization {
            windows.append(UsageWindow(label: "5h", usedPercent: used, resetsAt: parseDate(w.resetsAt)))
        }
        if let w = response.sevenDay, let used = w.utilization {
            windows.append(UsageWindow(label: "7d", usedPercent: used, resetsAt: parseDate(w.resetsAt)))
        }
        return windows
    }

    // MARK: - Credentials

    /// In-memory cache of the OAuth access token so we only hit the Keychain
    /// once per process lifetime. Keychain access to another app's item
    /// triggers a macOS authorization prompt; caching avoids repeated prompts.
    private static var _cachedToken: String?
    private static var _tokenFailed: Bool = false

    /// Reads the OAuth access token from the Claude Code CLI credentials.
    /// Tries on-disk credential files first, then Keychain as a fallback.
    /// Keychain access may trigger a one-time authorization prompt;
    /// subsequent calls return the in-memory copy.
    private static func readAccessToken() -> String? {
        if let token = _cachedToken {
            return token
        }
        if _tokenFailed {
            return nil
        }

        // 1. On-disk credential files — zero authorization prompts.
        //    Claude Code writes the full OAuth JSON here on every login;
        //    unlike Keychain, files have no size limit and no ACL barrier.
        for fileURL in credentialFileURLs {
            if let token = readTokenFromFile(at: fileURL) {
                _cachedToken = token
                return token
            }
        }

        // 2. Keychain (last resort — one-time macOS auth dialog if the file
        //    is missing; after user clicks Allow, subsequent calls use cache)
        if let token = readTokenFromKeychain() {
            _cachedToken = token
            return token
        }

        _tokenFailed = true
        return nil
    }

    /// Reads the access token from the Keychain.
    private static func readTokenFromKeychain() -> String? {
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
            return nil
        }
        return token
    }

    /// Reads the access token from an on-disk credential JSON file.
    /// Uses the same JSON structure as the Keychain item.
    private static func readTokenFromFile(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }
}
