//
//  ClaudeUsageService.swift
//  Light Stats
//
//  Created on 2026/06/10.
//
//  Logic chain — credential reading:
//
//  ┌─ readAccessToken() — actor-cached, expiry-aware ─────────┐
//  │  1. TokenCache.valid() → cache hit unless within 60s of  │
//  │     expiresAt (token lives only a few hours).            │
//  │  2. ~/.claude/.credentials.json       → file, 0 prompt   │
//  │  3. ~/.claude/credentials.json        → legacy, no dot   │
//  │  4. security find-generic-password -w → Keychain CLI     │
//  │     ^^^ /usr/bin/security subprocess — NO auth dialog    │
//  │     (unlike SecItemCopyMatching).                        │
//  │     Reference: Claude-Usage-Tracker                      │
//  │     (hamed-elfayome/Claude-Usage-Tracker).               │
//  │  5. Truncated JSON fallback: regex "accessToken":"..."   │
//  │     (expiry unknown → recovery relies on the 401 signal).│
//  └──────────────────────────────────────────────────────────┘
//                           │
//  ┌─ fetch() — three-source fallback ────────────────────────┐
//  │  1. GET api.anthropic.com/api/oauth/usage (OAuth API)    │
//  │     ↓ 401/403 → recoverFromExpiredToken():               │
//  │       invalidate cache → re-read → retry once → CLI PTY  │
//  │     ↓ 404/decoding/network failure                       │
//  │  2. POST api.anthropic.com/v1/messages (1-token Haiku)   │
//  │     Parse rate-limit response headers                    │
//  │     ↓ failure                                            │
//  │  3. launch `claude` in PTY, send /usage, parse TUI       │
//  │     (ultimate fallback — no network needed)              │
//  └──────────────────────────────────────────────────────────┘
//

import Foundation
import os

/// Fetches Claude Code subscription usage.
/// Credentials are maintained by the Claude Code CLI; we only read them.
///
/// Three-source fallback chain (OAuth → Messages API → CLI PTY):
/// 1. OAuth usage endpoint (GET api.anthropic.com/api/oauth/usage)
/// 2. Messages API rate-limit headers (1-token Haiku request)
/// 3. CLI PTY — launches `claude`, sends `/usage` in a pseudo-terminal, parses output
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

private struct CachedCredential {
    let token: String
    let expiresAt: Date?   // nil when unknown (e.g. truncated Keychain JSON)
}

/// Parses the `claudeAiOauth` credential JSON into a token + expiry.
/// Falls back to a regex extraction when the JSON is truncated (Keychain limit);
/// in that case the expiry is unknown and recovery relies on the 401 signal.
/// Reference: Claude-Usage-Tracker's Keychain truncation recovery.
private func parseClaudeCredential(from data: Data) -> CachedCredential? {
    guard !data.isEmpty else { return nil }
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let oauth = json["claudeAiOauth"] as? [String: Any],
       let token = oauth["accessToken"] as? String, !token.isEmpty {
        return CachedCredential(token: token, expiresAt: parseClaudeExpiry(oauth["expiresAt"]))
    }
    if let text = String(data: data, encoding: .utf8),
       let regex = try? NSRegularExpression(pattern: #""accessToken"\s*:\s*"([^"]+)""#),
       let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
       match.numberOfRanges >= 2,
       let range = Range(match.range(at: 1), in: text) {
        return CachedCredential(token: String(text[range]), expiresAt: nil)
    }
    return nil
}

/// Converts the millisecond-epoch `expiresAt` field into a Date.
private func parseClaudeExpiry(_ value: Any?) -> Date? {
    guard let milliseconds = value as? Double, milliseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: milliseconds / 1000)
}

/// Serialises access to the cached OAuth token (eliminates the data race on a
/// shared mutable static). The token is short-lived — it expires every few hours
/// and the Claude Code CLI refreshes it on disk/Keychain. We cache to avoid
/// re-reading on every poll, but honour `expiresAt` (with a 60s margin) and allow
/// forced invalidation when the server rejects a token early.
private actor ClaudeTokenCache {
    private var token: String?
    private var expiresAt: Date?
    private let margin: TimeInterval = 60

    func valid() -> String? {
        guard let token, !token.isEmpty else { return nil }
        if let expiresAt, Date() >= expiresAt.addingTimeInterval(-margin) { return nil }
        return token
    }

    func store(_ credential: CachedCredential) {
        token = credential.token
        expiresAt = credential.expiresAt
    }

    func invalidate() {
        token = nil
        expiresAt = nil
    }
}

enum ClaudeUsageService {

    private static let log = Logger(subsystem: "com.lightstats.app", category: "ClaudeUsage")

    private static let keychainService = "Claude Code-credentials"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Paths for on-disk credential files (read when Keychain is unavailable/truncated).
    private static var credentialFileURLs: [URL] {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        return [
            claudeDir.appendingPathComponent(".credentials.json"),
            claudeDir.appendingPathComponent("credentials.json")   // legacy path (no dot)
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
        guard let token = await readAccessToken() else {
            throw AIUsageError.credentialsMissing
        }

        // 1. Try the OAuth usage endpoint.
        let oauthResult = await fetchOAuthUsage(token: token)

        if case .failure(let error) = oauthResult {
            switch error {
            case .credentialsMissing:
                throw error
            case .tokenExpired:
                // The token we read is stale. The CLI may have refreshed it on
                // disk/Keychain since; re-read and retry, then fall through to the
                // CLI PTY (which reads the CLI's own fresh credentials). Sending the
                // known-expired token to the Messages API would only 401 again.
                return try await recoverFromExpiredToken(previousToken: token)
            case .endpointNotFound, .decoding, .network:
                // 2. Endpoint moved / response shape changed: read rate-limit headers.
                do {
                    return try await fetchUsageFromHeaders(token: token)
                } catch {
                    // 3. Messages API also failed — last resort is the CLI PTY,
                    //    which needs no network and reads usage from local `claude`.
                    return try await fetchUsageFromCLI()
                }
            }
        }

        return try oauthResult.get()
    }

    /// Recovers from a rejected (expired/revoked) token. Invalidates the cache,
    /// re-reads credentials, and — if the CLI has since refreshed the token —
    /// retries the OAuth endpoint once. Otherwise falls back to the CLI PTY,
    /// which launches `claude` and reads its own freshly-refreshed credentials.
    private static func recoverFromExpiredToken(previousToken: String) async throws -> ProviderUsageSnapshot {
        await tokenCache.invalidate()

        if let fresh = await readAccessToken(), fresh != previousToken {
            let retry = await fetchOAuthUsage(token: fresh)
            if case .success(let snapshot) = retry { return snapshot }
            // Refreshed token failed for a non-auth reason — try the header path.
            if case .failure(let err) = retry, err != .tokenExpired,
               let snapshot = try? await fetchUsageFromHeaders(token: fresh) {
                return snapshot
            }
        }

        return try await fetchUsageFromCLI()
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

        guard let windows = try? parseUsageJSON(data), !windows.isEmpty else {
            return .failure(.decoding)
        }

        return .success(ProviderUsageSnapshot(provider: .claude, windows: windows, fetchedAt: Date()))
    }

    // MARK: - Messages API fallback (rate-limit headers)

    /// Sends a minimal Messages API request (Haiku, 1 output token) solely to
    /// read rate-limit response headers. Token cost is negligible (~10 input
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

    /// Testable seam (also the live decode path): JSON body → usage windows, no network.
    static func parseUsageJSON(_ data: Data) throws -> [UsageWindow] {
        guard let decoded = try? JSONDecoder().decode(UsageResponse.self, from: data) else { throw AIUsageError.decoding }
        return parseWindows(from: decoded)
    }

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

    // MARK: - CLI PTY fallback (last resort)

    /// Launches `claude` inside a pseudo-terminal, sends `/usage`, and parses
    /// the TUI-rendered usage panel. This is the ultimate fallback — it requires
    /// no network access and works as long as `claude` is installed and logged in.
    ///
    /// Reference: CodexBar's ClaudeCLISession / ClaudeStatusProbe (steipete/CodexBar).
    private static let cliTimeout: TimeInterval = 14

    private static func fetchUsageFromCLI() async throws -> ProviderUsageSnapshot {
        guard let claudePath = resolveClaudeBinary() else {
            throw AIUsageError.credentialsMissing
        }

        let output = try await PTYProbe.capture(binary: claudePath, timeout: cliTimeout, config: cliProbeConfig())
        return try parseCLIOutput(output)
    }

    private static func resolveClaudeBinary() -> String? {
        CLIBinaryResolver.resolveClaudeBinary()
    }

    /// PTY config for `claude /usage`: launch headless (`--bare`), send `/usage`,
    /// and complete once the "Current session … N%" panel has rendered.
    private static func cliProbeConfig() -> PTYProbe.Config {
        PTYProbe.Config(
            arguments: ["--bare", "--allowed-tools", ""],
            winsize: winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0),
            initialDelay: 2.5,
            command: "/usage\r\n",
            pollInterval: 0.06,
            settleDelay: 1.0,
            workDirPrefix: "lightstats-claude-probe-",
            onOutput: { clean, _ in hasSessionValue(clean) ? .complete : .keepReading }
        )
    }

    // MARK: - CLI output parsing

    /// Returns true when the normalized text contains "Current session" immediately
    /// followed by a percentage value somewhere after it.
    private static func hasSessionValue(_ text: String) -> Bool {
        let normalized = text.lowercased().filter { !$0.isWhitespace }
        guard let labelRange = normalized.range(of: "currentsession") else { return false }
        let tail = normalized[labelRange.upperBound...]
        return tail.range(of: #"[0-9]{1,3}(\.?[0-9]+)?%"#, options: .regularExpression) != nil
    }

    /// Parses `claude /usage` TUI output into usage windows.
    /// Handles both "X% used" and "X% left" conventions.
    private static func parseCLIOutput(_ rawText: String) throws -> ProviderUsageSnapshot {
        let text = PTYProbe.stripANSICodes(rawText)

        // Trim to the last "Settings: … Usage …" panel to avoid earlier screen fragments.
        let panelText: String
        if let settingsRange = text.range(of: "Settings:", options: [.caseInsensitive, .backwards]) {
            let tail = String(text[settingsRange.lowerBound...])
            panelText = tail.range(of: "Usage", options: .caseInsensitive) != nil ? tail : text
        } else {
            panelText = text
        }

        // Detect error states.
        let lower = panelText.lowercased()
        if lower.contains("failed to load usage data") {
            throw AIUsageError.network
        }
        if lower.contains("token") && lower.contains("expired") {
            throw AIUsageError.tokenExpired
        }
        let compact = lower.filter { !$0.isWhitespace }
        if compact.contains("currentlyusingyoursubscription")
            && compact.contains("claudecodeusage")
            && !compact.contains("currentsession") {
            throw AIUsageError.network
        }

        // Parse session percentage.
        guard let sessionPercent = extractPercent(nearLabel: "Current session", in: panelText) else {
            throw AIUsageError.decoding
        }

        let weeklyPercent = extractPercent(nearLabel: "Current week (all models)", in: panelText)

        let sessionUsed = sessionPercent.isLeft ? 100 - sessionPercent.value : sessionPercent.value
        let weeklyUsed = weeklyPercent.map { $0.isLeft ? 100 - $0.value : $0.value }

        let sessionReset = extractReset(nearLabel: "Current session", in: panelText)
        let weeklyReset = weeklyPercent != nil
            ? extractReset(nearLabel: "Current week (all models)", in: panelText)
            : nil

        var windows: [UsageWindow] = [
            UsageWindow(
                label: "5h",
                usedPercent: min(100, max(0, sessionUsed)),
                resetsAt: parseResetDate(sessionReset)
            )
        ]
        if let wu = weeklyUsed {
            windows.append(UsageWindow(
                label: "7d",
                usedPercent: min(100, max(0, wu)),
                resetsAt: parseResetDate(weeklyReset)
            ))
        }

        return ProviderUsageSnapshot(provider: .claude, windows: windows, fetchedAt: Date())
    }

    /// Represents a parsed percentage that may be "left" or "used".
    private struct ParsedPercent: Equatable {
        let value: Double
        let isLeft: Bool  // true = remaining, false = used
    }

    /// Scans lines near a label for a percentage value.
    private static func extractPercent(nearLabel label: String, in text: String) -> ParsedPercent? {
        let lines = text.components(separatedBy: .newlines)
        let normalizedLabel = alphanumericOnly(label.lowercased())
        let normalizedLines = lines.map { alphanumericOnly($0.lowercased()) }

        guard let idx = normalizedLines.firstIndex(where: { $0.contains(normalizedLabel) }) else {
            return nil
        }

        // Scan a window of lines after the label for a percentage.
        let window = lines.dropFirst(idx).prefix(12)
        for line in window {
            if let pct = percentFromCLILine(line) { return pct }
        }
        return nil
    }

    /// Extracts a percentage from a single line.
    /// Handles both "42% used" and "58% left" conventions.
    /// Returns nil for lines that look like status context meters (contain model names + |).
    private static func percentFromCLILine(_ line: String) -> ParsedPercent? {
        let lower = line.lowercased()
        // Skip status context lines like "opus | 0%"
        if lower.contains("|") {
            let modelTokens = ["opus", "sonnet", "haiku", "default"]
            if modelTokens.contains(where: lower.contains) { return nil }
        }

        guard let regex = try? NSRegularExpression(pattern: #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%"#) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 2,
              let valRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let value = Double(line[valRange]) ?? 0
        let clamped = max(0, min(100, value))

        let usedKeywords = ["used", "spent", "consumed"]
        let leftKeywords = ["left", "remaining", "available"]

        if usedKeywords.contains(where: lower.contains) {
            return ParsedPercent(value: 100 - clamped, isLeft: false)
        }
        if leftKeywords.contains(where: lower.contains) {
            return ParsedPercent(value: clamped, isLeft: true)
        }
        // Default: assume the percentage shown is "remaining" (matches Claude's TUI).
        return ParsedPercent(value: clamped, isLeft: true)
    }

    /// Strips non-alphanumeric characters from a string. Used for fuzzy label matching
    /// against PTY output where ANSI codes and spacing vary.
    private static func alphanumericOnly(_ s: String) -> String {
        String(s.unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    /// Extracts a reset description near a label.
    private static func extractReset(nearLabel label: String, in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let normalizedLabel = alphanumericOnly(label.lowercased())
        let normalizedLines = lines.map { alphanumericOnly($0.lowercased()) }

        guard let idx = normalizedLines.firstIndex(where: { $0.contains(normalizedLabel) }) else {
            return nil
        }

        let window = lines.dropFirst(idx).prefix(14)
        for line in window {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let normLine = alphanumericOnly(trimmed.lowercased())
            // Break if we hit the next section label.
            if normLine.hasPrefix("current"), !normLine.contains(normalizedLabel) { break }
            if let resetRange = trimmed.range(
                of: "Resets",
                options: NSString.CompareOptions.caseInsensitive
            ) {
                return String(trimmed[resetRange.lowerBound...])
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " )"))
            }
        }
        return nil
    }

    /// Parses a reset string like "Resets in 2h 15m" or "Resets Jun 15 at 3:00pm" into a Date.
    private static func parseResetDate(_ raw: String?) -> Date? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        // Strip "Resets" or "Resets:" prefix and "at".
        text = text.replacingOccurrences(
            of: #"(?i)^resets?:?\s*"#,
            with: "",
            options: .regularExpression)
        text = text.replacingOccurrences(of: " at ", with: " ", options: .caseInsensitive)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse relative duration like "2h 15m" or "45m".
        if let relative = parseRelativeReset(text) { return relative }

        return nil
    }

    /// Parses relative reset strings like "2h 15m", "45m", "3d 4h".
    private static func parseRelativeReset(_ text: String) -> Date? {
        let lower = text.lowercased()
        var totalSeconds: TimeInterval = 0

        // Match patterns like "2h", "15m", "3d"
        let pattern = #"([0-9]+)\s*(d|h|m|s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        let matches = regex.matches(in: lower, range: range)
        guard !matches.isEmpty else { return nil }

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let numRange = Range(match.range(at: 1), in: lower),
                  let unitRange = Range(match.range(at: 2), in: lower),
                  let value = Double(lower[numRange]) else { continue }
            switch lower[unitRange] {
            case "d": totalSeconds += value * 86400
            case "h": totalSeconds += value * 3600
            case "m": totalSeconds += value * 60
            case "s": totalSeconds += value
            default: break
            }
        }

        guard totalSeconds > 0 else { return nil }
        return Date().addingTimeInterval(totalSeconds)
    }

    // MARK: - Credentials

    private static let tokenCache = ClaudeTokenCache()

    /// Reads the OAuth access token: in-memory cache first, then on-disk credential
    /// files (zero prompt), then the Keychain via `/usr/bin/security` (no auth
    /// dialog, unlike `SecItemCopyMatching`). The cache self-expires near `expiresAt`,
    /// so a stale token is never returned across the token's few-hour lifetime.
    private static func readAccessToken() async -> String? {
        if let token = await tokenCache.valid() { return token }

        for fileURL in credentialFileURLs {
            if let data = try? Data(contentsOf: fileURL), let cred = parseClaudeCredential(from: data) {
                await tokenCache.store(cred)
                log.info("Claude token read from credential file")
                return cred.token
            }
        }

        if let data = readKeychainData(), let cred = parseClaudeCredential(from: data) {
            await tokenCache.store(cred)
            log.info("Claude token read from Keychain (security CLI)")
            return cred.token
        }

        log.error("Claude credentials unavailable")
        return nil
    }

    /// Clears the cached token so the next fetch re-reads credentials. Called on
    /// manual retry. The fetch path also self-recovers on a 401, so this is a
    /// best-effort nudge — the brief async gap before invalidation is benign.
    static func resetCredentialCache() {
        Task { await tokenCache.invalidate() }
    }

    /// Reads the raw Keychain credential blob via the shared `security` CLI
    /// reader (no auth dialog, unlike `SecItemCopyMatching`).
    private static func readKeychainData() -> Data? {
        KeychainCredentialReader.readGenericPassword(service: keychainService)
    }
}
