//
//  CodexUsageService.swift
//  Light Stats
//
//  Created on 2026/06/10.
//

import Foundation

/// Fetches Codex subscription usage via the ChatGPT backend usage endpoint.
/// Credentials are maintained by the Codex CLI in ~/.codex/auth.json; we only read them.
enum CodexUsageService {

    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private static var authFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    // MARK: - Response models (verified against a real response on 2026-06-10)

    private struct UsageResponse: Decodable {
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case rateLimit = "rate_limit"
        }

        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?

            enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
                case secondaryWindow = "secondary_window"
            }
        }

        struct Window: Decodable {
            let usedPercent: Double?
            let limitWindowSeconds: Int?
            let resetAt: Double?   // Unix epoch seconds

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case limitWindowSeconds = "limit_window_seconds"
                case resetAt = "reset_at"
            }
        }
    }

    private struct Credentials {
        let accessToken: String
        let accountId: String
    }

    // MARK: - Fetch

    static func fetch() async throws -> ProviderUsageSnapshot {
        guard let creds = readCredentials() else {
            throw AIUsageError.credentialsMissing
        }

        do {
            return try await fetchOnce(with: creds)
        } catch AIUsageError.tokenExpired {
            // The Codex CLI may have refreshed the token since we read it; re-read and retry once.
            guard let fresh = readCredentials(), fresh.accessToken != creds.accessToken else {
                throw AIUsageError.tokenExpired
            }
            return try await fetchOnce(with: fresh)
        }
    }

    private static func fetchOnce(with creds: Credentials) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(creds.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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

        var windows: [UsageWindow] = []
        if let w = decoded.rateLimit?.primaryWindow, let used = w.usedPercent {
            windows.append(usageWindow(from: w, usedPercent: used))
        }
        if let w = decoded.rateLimit?.secondaryWindow, let used = w.usedPercent {
            windows.append(usageWindow(from: w, usedPercent: used))
        }

        guard !windows.isEmpty else { throw AIUsageError.decoding }

        return ProviderUsageSnapshot(provider: .codex, windows: windows, fetchedAt: Date())
    }

    private static func usageWindow(from window: UsageResponse.Window, usedPercent: Double) -> UsageWindow {
        let resetsAt = window.resetAt.map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(
            label: windowLabel(seconds: window.limitWindowSeconds),
            usedPercent: usedPercent,
            resetsAt: resetsAt
        )
    }

    /// 18000 → "5h", 604800 → "7d"
    private static func windowLabel(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        if seconds >= 86_400 {
            return "\(seconds / 86_400)d"
        }
        return "\(seconds / 3_600)h"
    }

    // MARK: - Credentials

    private static func readCredentials() -> Credentials? {
        guard let data = try? Data(contentsOf: authFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              let accountId = tokens["account_id"] as? String,
              !accessToken.isEmpty, !accountId.isEmpty else {
            return nil
        }
        return Credentials(accessToken: accessToken, accountId: accountId)
    }
}
