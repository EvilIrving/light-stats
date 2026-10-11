//
//  AntigravityUsageService.swift
//  Light Stats
//
//  Quota for the Antigravity CLI (`agy`). Three measured facts shape this file:
//
//  1. `agy` keeps its OAuth grant in macOS Keychain as a generic password
//     (service `gemini`, account `antigravity`) whose value is
//     `go-keyring-base64:` plus base64 of
//     `{"token": {"access_token", "refresh_token", "expiry"}}`.
//  2. The quota service is licence-gated on caller identity: a request whose
//     User-Agent does not name Antigravity is refused with 403, no matter how
//     valid its token. Sending the CLI's own user agent is what makes the read
//     legal for the server.
//  3. The refresh token is bound to the Cloud Code Assist OAuth client both
//     CLIs ship; a grant from any other client is rejected. That client is
//     public — every install embeds it — not a user credential.
//
//  The Keychain item stays `agy`'s: a token refreshed here lives in this
//  process only, never written back.
//

import Foundation

/// Antigravity CLI quota. See the file header for the measured credential,
/// user-agent, and OAuth-client facts.
nonisolated enum AntigravityUsageService: UsageProviding {
    static var id: AIProvider { .antigravity }

    private static let log = AppLogger(category: "AntigravityUsage")

    private static let keychainService = "gemini"
    private static let keychainAccount = "antigravity"
    private static let keyringPrefix = "go-keyring-base64:"

    private static let quotaSummaryURL = URL(
        string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
    )!
    private static let tokenRefreshURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let userAgent = "antigravity-cli"

    private static let oauthClient = OAuthClient(
        id: "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com",
        secret: "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"
    )

    private static let tokenCache = AntigravityTokenCache()

    // MARK: - Fetch

    static func fetch() async throws -> ProviderUsageSnapshot {
        let credential = try readCredential()
        let token = try await accessToken(from: credential)

        do {
            return try await fetchSummary(accessToken: token)
        } catch AIUsageError.tokenExpired {
            // The server rejected a token our stored expiry still called valid
            // (revoked early, or `agy` refreshed the item behind us).
            let refreshed = try await refreshAccessToken(credential)
            return try await fetchSummary(accessToken: refreshed)
        }
    }

    /// Clears the in-process token so the next fetch re-reads the Keychain `agy`
    /// wrote. Called on manual retry; the fetch path also self-recovers on 401.
    static func resetCredentialCache() {
        Task { await tokenCache.invalidate() }
    }

    private static func fetchSummary(accessToken: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: quotaSummaryURL, timeoutInterval: UsageHTTPClient.defaultTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("{}".utf8)

        return try parseQuotaSummary(try await UsageHTTPClient.send(request))
    }

    // MARK: - Credential

    struct Credential: Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiry: Date?
    }

    private struct OAuthClient {
        let id: String
        let secret: String
    }

    /// Testable seam: decode the blob `agy` stored. Returns nil when the item is
    /// absent or does not carry the grant shape.
    static func decodeCredential(_ raw: Data) -> Credential? {
        guard let text = String(data: raw, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(keyringPrefix),
              let encoded = Data(base64Encoded: String(trimmed.dropFirst(keyringPrefix.count))),
              let json = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              let token = json["token"] as? [String: Any],
              let accessToken = token["access_token"] as? String,
              !accessToken.isEmpty else {
            return nil
        }

        let refreshToken = token["refresh_token"] as? String
        return Credential(
            accessToken: accessToken,
            refreshToken: (refreshToken?.isEmpty == false) ? refreshToken : nil,
            expiry: date(token["expiry"])
        )
    }

    private static func readCredential() throws -> Credential {
        guard let raw = KeychainCredentialReader.readGenericPassword(
            service: keychainService,
            account: keychainAccount
        ), let credential = decodeCredential(raw) else {
            throw AIUsageError.credentialsMissing
        }
        return credential
    }

    /// The stored token while it is unexpired, else a token this process
    /// refreshed earlier, else a fresh refresh grant. An absent expiry is
    /// trusted and left to the 401 path.
    private static func accessToken(from credential: Credential) async throws -> String {
        if credential.expiry.map({ $0 > Date().addingTimeInterval(60) }) != false {
            return credential.accessToken
        }
        if let cached = await tokenCache.valid() {
            return cached
        }
        return try await refreshAccessToken(credential)
    }

    private static func refreshAccessToken(_ credential: Credential) async throws -> String {
        guard let refreshToken = credential.refreshToken else {
            throw AIUsageError.tokenExpired
        }

        var request = URLRequest(url: tokenRefreshURL, timeoutInterval: UsageHTTPClient.defaultTimeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = tokenRequestBody(refreshToken: refreshToken).data(using: .utf8)

        let data: Data
        do {
            data = try await UsageHTTPClient.send(request)
        } catch {
            log.error("Antigravity token refresh failed: \(error)")
            throw error
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              !token.isEmpty else {
            throw AIUsageError.decoding
        }

        let expiresAt = double(json["expires_in"]).map { Date().addingTimeInterval($0) }
        await tokenCache.store(token: token, expiresAt: expiresAt)
        return token
    }

    private static func tokenRequestBody(refreshToken: String) -> String {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: oauthClient.id),
            URLQueryItem(name: "client_secret", value: oauthClient.secret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        return components.percentEncodedQuery ?? ""
    }

    // MARK: - Parsing

    /// Testable seam (also the live parse path): decode a
    /// `retrieveUserQuotaSummary` body with no network. Throws `.decoding` when
    /// no bucket can be read.
    static func parseQuotaSummary(_ data: Data) throws -> ProviderUsageSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = json["groups"] as? [[String: Any]] else {
            throw AIUsageError.decoding
        }

        let windows = tightestWindows(in: groups)
        guard !windows.isEmpty else { throw AIUsageError.decoding }

        return ProviderUsageSnapshot(provider: id, windows: windows, fetchedAt: Date())
    }

    /// The body meters one subscription twice — a Gemini group and a
    /// Claude/GPT group, a 5h and a weekly bucket each. The row reports the
    /// tighter bucket per window, which is the allowance that runs out first.
    private static func tightestWindows(in groups: [[String: Any]]) -> [UsageWindow] {
        var tightest: [String: UsageWindow] = [:]

        for group in groups {
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                guard let kind = windowKind(of: bucket),
                      let remaining = double(bucket["remainingFraction"]) else { continue }

                let usedPercent = min(100, max(0, (1 - remaining) * 100))
                guard usedPercent > (tightest[kind]?.usedPercent ?? -1) else { continue }

                tightest[kind] = UsageWindow(
                    label: kind,
                    usedPercent: usedPercent,
                    resetsAt: date(bucket["resetTime"])
                )
            }
        }

        return ["5h", "7d"].compactMap { tightest[$0] }
    }

    /// `weekly` is the panel's `7d` row. An unrecognized window is skipped
    /// rather than labelled with a guess.
    private static func windowKind(of bucket: [String: Any]) -> String? {
        guard let window = (bucket["window"] as? String)?.lowercased() else { return nil }
        switch window {
        case "5h": return "5h"
        case "weekly": return "7d"
        default: return nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Holds a token refreshed during this process. `agy` remains the Keychain
/// item's only writer, so nothing here is persisted.
private actor AntigravityTokenCache {
    private var token: String?
    private var expiresAt: Date?
    private let margin: TimeInterval = 60

    func valid() -> String? {
        guard let token, !token.isEmpty else { return nil }
        if let expiresAt, Date() >= expiresAt.addingTimeInterval(-margin) { return nil }
        return token
    }

    func store(token: String, expiresAt: Date?) {
        self.token = token
        self.expiresAt = expiresAt
    }

    func invalidate() {
        token = nil
        expiresAt = nil
    }
}
