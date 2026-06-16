//
//  CodexUsageService.swift
//  Light Stats
//
//  Created on 2026/06/10.
//

import Foundation

/// Fetches Codex subscription usage with two-source fallback.
/// Credentials are maintained by the Codex CLI in ~/.codex/auth.json; we only read them.
///
/// Two-source fallback chain (API → CLI PTY):
/// 1. ChatGPT backend usage endpoint (chatgpt.com/backend-api/wham/usage)
/// 2. CLI PTY — launches `codex`, sends `/status`, parses TUI output
///
/// API contract (undocumented endpoint, verified against a real 200 response on
/// 2026-06-10 — decode defensively):
/// - Request:  `GET https://chatgpt.com/backend-api/wham/usage`
/// - Headers:  `Authorization: Bearer <access_token>`
///             `ChatGPT-Account-Id: <account_id>`
///             `Accept: application/json`
/// - Auth:     `~/.codex/auth.json` → `tokens.access_token` + `tokens.account_id`.
///             Read-only; on 401 we re-read the file (CLI may have refreshed) and retry once.
/// - Response: `{ "rate_limit": { "primary_window": Window, "secondary_window": Window } }`
///             where `Window = { used_percent: 0–100, limit_window_seconds: Int,
///             reset_at: Unix epoch seconds (NOT ISO8601) }`. `plan_type` also present.
/// - Errors:   401/403 → token expired. All fields optional so a renamed field
///             degrades to stale rather than crashing; one window decoding fail
///             doesn't sink the other.
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
            // No credentials — try CLI PTY as fallback (works when codex is logged in).
            return try await fetchUsageFromCLI()
        }

        do {
            return try await fetchOnce(with: creds)
        } catch AIUsageError.tokenExpired {
            // The Codex CLI may have refreshed the token since we read it; re-read and retry once.
            guard let fresh = readCredentials(), fresh.accessToken != creds.accessToken else {
                // Token expired and not refreshed — fall back to CLI PTY.
                return try await fetchUsageFromCLI()
            }
            return try await fetchOnce(with: fresh)
        } catch {
            // API failed for any other reason — fall back to CLI PTY.
            return try await fetchUsageFromCLI()
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

    // MARK: - CLI PTY fallback

    /// Launches `codex` inside a pseudo-terminal, sends `/status`, and parses
    /// the TUI-rendered status panel. Used as fallback when the API endpoint
    /// is unreachable or credentials are missing.
    ///
    /// Reference: CodexBar's CodexCLISession / CodexStatusProbe (steipete/CodexBar).
    private static let cliTimeout: TimeInterval = 10

    private static func fetchUsageFromCLI() async throws -> ProviderUsageSnapshot {
        guard let codexPath = resolveCodexBinary() else {
            throw AIUsageError.credentialsMissing
        }

        let output = try await capturePTYOutput(binary: codexPath, timeout: cliTimeout)
        return try parseCLIOutput(output)
    }

    private static func resolveCodexBinary() -> String? {
        if let envPath = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"],
           !envPath.isEmpty,
           FileManager.default.isExecutableFile(atPath: envPath) {
            return envPath
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["codex"]
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

    /// Creates a PTY pair, launches `codex` inside it, sends `/status`,
    /// and captures all output until we have status data or timeout.
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
        var win = winsize(ws_row: 60, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)

        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw AIUsageError.network
        }
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        defer {
            close(primaryFD)
            close(secondaryFD)
        }

        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: false)
        defer { try? secondaryHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = []
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle
        process.environment = ProcessInfo.processInfo.environment

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightstats-codex-probe-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        process.currentDirectoryURL = workDir

        guard let _ = try? process.run() else {
            throw AIUsageError.network
        }
        defer {
            if process.isRunning {
                process.terminate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }

        // Wait for codex to initialize.
        Thread.sleep(forTimeInterval: 0.5)

        // Send /status command.
        _ = try? writeAll(primaryFD, data: "/status\r\n".data(using: .utf8)!)

        var allOutput = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var hasStatus = false
        var updateDismissed = false

        while Date() < deadline {
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = read(primaryFD, &buf, buf.count)
            if n > 0 {
                allOutput.append(contentsOf: buf.prefix(n))

                if let text = String(data: allOutput, encoding: .utf8) {
                    let clean = stripANSICodes(text)
                    let lower = clean.lowercased()

                    // Auto-dismiss update prompts ("Update available! Run bun install …").
                    if !updateDismissed,
                       lower.contains("update available"),
                       lower.contains("codex") {
                        // Send down-arrow + Enter to skip the update prompt.
                        _ = try? writeAll(primaryFD, data: Data([0x1B, 0x5B, 0x42]))
                        Thread.sleep(forTimeInterval: 0.12)
                        _ = try? writeAll(primaryFD, data: "\r".data(using: .utf8)!)
                        Thread.sleep(forTimeInterval: 0.15)
                        _ = try? writeAll(primaryFD, data: "/status\r\n".data(using: .utf8)!)
                        updateDismissed = true
                        allOutput.removeAll()
                        Thread.sleep(forTimeInterval: 0.3)
                        continue
                    }

                    // Detect status markers.
                    if lower.contains("5h limit") || lower.contains("5-hour limit")
                        || lower.contains("weekly limit") || lower.contains("credits:") {
                        hasStatus = true
                        // Settle period.
                        Thread.sleep(forTimeInterval: 1.0)
                        var finalBuf = [UInt8](repeating: 0, count: 8192)
                        let finalN = read(primaryFD, &finalBuf, finalBuf.count)
                        if finalN > 0 { allOutput.append(contentsOf: finalBuf.prefix(finalN)) }
                        break
                    }
                }
            }
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.12)
        }

        guard hasStatus,
              let text = String(data: allOutput, encoding: .utf8),
              !text.isEmpty else {
            throw AIUsageError.network
        }

        return text
    }

    private static func writeAll(_ fd: Int32, data: Data) throws {
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

    /// Strips ANSI escape sequences.
    private static func stripANSICodes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]") else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// Parses `codex /status` TUI output into usage windows.
    /// Handles "5h limit" / "5-hour limit" and "Weekly limit" rows.
    private static func parseCLIOutput(_ rawText: String) throws -> ProviderUsageSnapshot {
        let text = stripANSICodes(rawText)
        let lower = text.lowercased()

        if lower.contains("data not available yet") {
            throw AIUsageError.network
        }

        let pattern = #"(?:5h?\s*limit|5-hour\s*limit|weekly\s*limit)\s+([0-9]{1,3})\s*%\s*(left|remaining|available)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        var fiveHourPercentLeft: Double?
        var fiveHourReset: String?
        var weeklyPercentLeft: Double?
        var weeklyReset: String?

        if let regex {
            for match in regex.matches(in: text, range: range) {
                guard match.numberOfRanges >= 3,
                      let labelRange = Range(match.range(at: 0), in: text),
                      let pctRange = Range(match.range(at: 1), in: text),
                      let pct = Double(text[pctRange]) else { continue }
                let label = String(text[labelRange]).lowercased()
                let line = lineContaining(String(text[labelRange]), in: text)
                let reset = line.flatMap { extractReset($0) }

                if label.contains("5h") || label.contains("5-hour") {
                    fiveHourPercentLeft = pct
                    fiveHourReset = reset
                } else if label.contains("weekly") {
                    weeklyPercentLeft = pct
                    weeklyReset = reset
                }
            }
        }

        guard fiveHourPercentLeft != nil else {
            throw AIUsageError.decoding
        }

        let fiveHourUsed = 100 - (fiveHourPercentLeft ?? 0)
        var windows: [UsageWindow] = [
            UsageWindow(
                label: "5h",
                usedPercent: min(100, max(0, fiveHourUsed)),
                resetsAt: parseResetDate(fiveHourReset)
            )
        ]

        if let wpl = weeklyPercentLeft {
            windows.append(UsageWindow(
                label: "7d",
                usedPercent: min(100, max(0, 100 - wpl)),
                resetsAt: parseResetDate(weeklyReset)
            ))
        }

        return ProviderUsageSnapshot(provider: .codex, windows: windows, fetchedAt: Date())
    }

    /// Finds the full line containing a substring.
    private static func lineContaining(_ substring: String, in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            if line.localizedCaseInsensitiveContains(substring) { return line }
        }
        return nil
    }

    /// Extracts reset description from a line like "… Resets in 2h 15m".
    private static func extractReset(_ line: String) -> String? {
        guard let range = line.range(
            of: "Resets",
            options: NSString.CompareOptions.caseInsensitive
        ) else { return nil }
        return String(line[range.lowerBound...])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: " )"))
    }

    /// Parses a reset string like "Resets in 2h 15m" or "Resets at 3:00 PM".
    private static func parseResetDate(_ raw: String?) -> Date? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        text = text.replacingOccurrences(
            of: #"(?i)^resets?:?\s*"#,
            with: "",
            options: .regularExpression)
        text = text.replacingOccurrences(of: " at ", with: " ", options: .caseInsensitive)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let relative = parseRelativeReset(text) { return relative }
        return parseAbsoluteTime(text)
    }

    private static func parseRelativeReset(_ text: String) -> Date? {
        let lower = text.lowercased()
        var totalSeconds: TimeInterval = 0

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

        return totalSeconds > 0 ? Date().addingTimeInterval(totalSeconds) : nil
    }

    private static func parseAbsoluteTime(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.defaultDate = Date()

        for format in ["h:mm a", "HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                let calendar = Calendar(identifier: .gregorian)
                let comps = calendar.dateComponents([.hour, .minute], from: date)
                guard let anchored = calendar.date(
                    bySettingHour: comps.hour ?? 0,
                    minute: comps.minute ?? 0,
                    second: 0,
                    of: Date()) else { continue }
                return anchored >= Date()
                    ? anchored
                    : calendar.date(byAdding: .day, value: 1, to: anchored)
            }
        }
        return nil
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
