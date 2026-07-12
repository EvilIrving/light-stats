//
//  CodexUsageService.swift
//  Light Stats
//
//  Created on 2026/06/10.
//
//  Logic chain — credential reading:
//
//  ┌─ readCredentials() ──────────────────────────────────────┐
//  │  ~/.codex/auth.json  →  tokens.access_token              │
//  │                        + tokens.account_id                │
//  │  File I/O only, zero authorization prompt.               │
//  └──────────────────────────────────────────────────────────┘
//                           │
//  ┌─ fetch() — two-source fallback ──────────────────────────┐
//  │  1. No credentials → skip to CLI PTY (step 3)            │
//  │  2. GET chatgpt.com/backend-api/wham/usage               │
//  │     Header: Authorization: Bearer <access_token>          │
//  │             ChatGPT-Account-Id: <account_id>              │
//  │     ↓ 401 → re-read auth.json (CLI may have refreshed)   │
//  │       token changed → retry API once                     │
//  │       token unchanged → fall to CLI PTY                  │
//  │     ↓ any other error → fall to CLI PTY                  │
//  │  3. CLI PTY: launch `codex`, send /status, parse TUI     │
//  │     Auto-dismiss "Update available!" prompts             │
//  │     Parse: "5h limit X% left" + "Weekly limit X% left"   │
//  └──────────────────────────────────────────────────────────┘

import Foundation
import os

/// Codex (ChatGPT) subscription usage — see file header for full logic chain.
enum CodexUsageService {

    private static let log = AppLogger(category: "CodexUsage")

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
                log.error("Codex API token expired; trying CLI PTY fallback")
                return try await fetchUsageFromCLI(fallbackError: AIUsageError.tokenExpired)
            }
            return try await fetchOnce(with: fresh)
        } catch {
            // API failed for any other reason — fall back to CLI PTY.
            log.error("Codex API failed; trying CLI PTY fallback: \(describe(error))")
            return try await fetchUsageFromCLI(fallbackError: error)
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

        let windows = try parseUsageJSON(data)
        guard !windows.isEmpty else { throw AIUsageError.decoding }

        return ProviderUsageSnapshot(provider: .codex, windows: windows, fetchedAt: Date())
    }

    /// Testable seam: decode the usage JSON body into usage windows, with no
    /// network. Mirrors the decode + window-building step inside `fetchOnce`.
    /// Throws `.decoding` on malformed JSON; returns `[]` when neither rate-limit
    /// window is present (caller decides whether empty is an error).
    static func parseUsageJSON(_ data: Data) throws -> [UsageWindow] {
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
        return windows
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

    private static func fetchUsageFromCLI(fallbackError: Error? = nil) async throws -> ProviderUsageSnapshot {
        guard let codexPath = resolveCodexBinary() else {
            throw fallbackError ?? AIUsageError.credentialsMissing
        }

        do {
            let output = try await PTYProbe.capture(binary: codexPath, timeout: cliTimeout, config: cliProbeConfig())
            return try parseCLIOutput(output)
        } catch {
            if let fallbackError {
                log.error("Codex CLI PTY fallback failed: \(describe(error))")
                log.error("Codex initial API error: \(describe(fallbackError))")
            } else {
                log.error("Codex CLI PTY fallback failed: \(describe(error))")
            }
            throw fallbackError ?? error
        }
    }

    private static func describe(_ error: Error) -> String {
        if let aiError = error as? AIUsageError {
            return String(describing: aiError)
        }
        return error.localizedDescription
    }

    private static func resolveCodexBinary() -> String? {
        CLIBinaryResolver.resolveCodexBinary()
    }

    /// PTY config for `codex /status`: send `/status`, dismiss an "update
    /// available" banner if it appears (down-arrow → Enter → re-send `/status`),
    /// and complete once a limit/credits marker is on screen.
    private static func cliProbeConfig() -> PTYProbe.Config {
        var updateDismissed = false
        return PTYProbe.Config(
            arguments: [],
            winsize: winsize(ws_row: 60, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0),
            initialDelay: 0.5,
            command: "/status\r\n",
            pollInterval: 0.12,
            settleDelay: 1.0,
            workDirPrefix: "lightstats-codex-probe-",
            onOutput: { clean, write in
                let lower = clean.lowercased()
                // Auto-dismiss update prompts ("Update available! Run bun install …").
                if !updateDismissed, lower.contains("update available"), lower.contains("codex") {
                    write("\u{1B}[B")   // down-arrow
                    Thread.sleep(forTimeInterval: 0.12)
                    write("\r")
                    Thread.sleep(forTimeInterval: 0.15)
                    write("/status\r\n")
                    updateDismissed = true
                    Thread.sleep(forTimeInterval: 0.3)
                    return .reset
                }
                if lower.contains("5h limit") || lower.contains("5-hour limit")
                    || lower.contains("weekly limit") || lower.contains("credits:") {
                    return .complete
                }
                return .keepReading
            }
        )
    }

    // MARK: - CLI output parsing

    /// Parses `codex /status` TUI output into usage windows.
    /// Handles "5h limit" / "5-hour limit" and "Weekly limit" rows.
    private static func parseCLIOutput(_ rawText: String) throws -> ProviderUsageSnapshot {
        let text = PTYProbe.stripANSICodes(rawText)
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
        for line in text.components(separatedBy: .newlines) where line.localizedCaseInsensitiveContains(substring) {
            return line
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
