//
//  ClaudeUsageService.swift
//  Light Stats
//
//  Created on 2026/06/10.
//

import Foundation
import Security
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
            case .endpointNotFound, .decoding, .network:
                do {
                    return try await fetchUsageFromHeaders(token: token)
                } catch {
                    // 3. If Messages API also fails, fall back to CLI PTY as last resort.
                    //    This needs no network — it reads usage from the local `claude` CLI.
                    _ = error
                    return try await fetchUsageFromCLI()
                }
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

        let output = try await capturePTYOutput(binary: claudePath, timeout: cliTimeout)
        return try parseCLIOutput(output)
    }

    private static func resolveClaudeBinary() -> String? {
        // Check CLAUDE_CLI_PATH env var first, then PATH.
        if let envPath = ProcessInfo.processInfo.environment["CLAUDE_CLI_PATH"],
           !envPath.isEmpty,
           FileManager.default.isExecutableFile(atPath: envPath) {
            return envPath
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["claude"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Creates a PTY pair, launches `claude` inside it, sends `/usage`,
    /// and captures all output until session data appears or timeout.
    private static func capturePTYOutput(binary: String, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try capturePTYSync(binary: binary, timeout: timeout)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func capturePTYSync(binary: String, timeout: TimeInterval) throws -> String {
        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)

        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw AIUsageError.network
        }
        // Make primary non-blocking so we can poll.
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        defer {
            close(primaryFD)
            close(secondaryFD)
        }

        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: false)
        defer { try? secondaryHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--bare", "--allowed-tools", ""]
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle
        process.environment = ProcessInfo.processInfo.environment

        // Use a temp directory as working dir so claude doesn't pick up project CLAUDE.md.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightstats-claude-probe-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        process.currentDirectoryURL = workDir

        guard (try? process.run()) != nil else {
            throw AIUsageError.network
        }
        defer {
            if process.isRunning {
                process.terminate()
                // Escalate after a brief wait.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }

        // Wait for claude to initialize (CodexBar uses 2s; we use 2.5s for safety).
        Thread.sleep(forTimeInterval: 2.5)

        // Send /usage command.
        _ = try? writeToPTY(fd: primaryFD, text: "/usage\r\n")

        // Collect output until we have session data or timeout.
        var allOutput = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var hasSessionData = false

        while Date() < deadline {
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = read(primaryFD, &buf, buf.count)
            if n > 0 {
                allOutput.append(contentsOf: buf.prefix(n))
                // Check if we have enough data: look for "Current session" + a percentage.
                if let text = String(data: allOutput, encoding: .utf8) {
                    let clean = stripANSICodes(text)
                    if hasSessionValue(clean) {
                        hasSessionData = true
                        // Brief settle period.
                        Thread.sleep(forTimeInterval: 1.0)
                        // Final read.
                        var finalBuf = [UInt8](repeating: 0, count: 8192)
                        let finalN = read(primaryFD, &finalBuf, finalBuf.count)
                        if finalN > 0 { allOutput.append(contentsOf: finalBuf.prefix(finalN)) }
                        break
                    }
                }
            }
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.06)
        }

        guard hasSessionData,
              let text = String(data: allOutput, encoding: .utf8),
              !text.isEmpty else {
            throw AIUsageError.network
        }

        return text
    }

    private static func writeToPTY(fd: Int32, text: String) throws {
        guard let data = text.data(using: .utf8) else { return }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(fd, base.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        usleep(5000)
                        continue
                    }
                    throw AIUsageError.network
                }
                offset += written
            }
        }
    }

    // MARK: - CLI output parsing

    /// Strips ANSI escape sequences (CSI sequences: ESC [ ... ending in 0x40–0x7E).
    /// Reference: CodexBar TextParsing.stripANSICodes.
    private static func stripANSICodes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]") else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

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
        let text = stripANSICodes(rawText)

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
                log.info("Claude token read from credential file")
                _cachedToken = token
                return token
            }
        }

        // 2. Keychain (last resort — one-time macOS auth dialog if the file
        //    is missing; after user clicks Allow, subsequent calls use cache)
        let (token, status) = readTokenFromKeychain()
        if let token {
            log.info("Claude token read from Keychain")
            _cachedToken = token
            return token
        }

        // Only treat a *genuinely missing* item as a permanent failure. If the
        // user denied/cancelled the auth dialog (errSecUserCanceled /
        // errSecAuthFailed / errSecInteractionNotAllowed), keep the failure
        // transient so a manual retry re-prompts instead of failing instantly.
        let permanent = (status == errSecItemNotFound)
        log.error("Claude credentials unavailable (keychain status \(status), permanent: \(permanent))")
        _tokenFailed = permanent
        return nil
    }

    /// Clears the cached token / failure flag so the next fetch re-reads
    /// credentials (and may re-prompt for Keychain access). Called on manual retry.
    static func resetCredentialCache() {
        _cachedToken = nil
        _tokenFailed = false
    }

    /// Reads the access token from the Keychain, returning the raw OSStatus so
    /// the caller can distinguish "not found" from "user denied".
    private static func readTokenFromKeychain() -> (token: String?, status: OSStatus) {
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
            return (nil, status)
        }
        return (token, status)
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
