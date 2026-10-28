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
//  4. The group summary stopped returning the Gemini group (backend change);
//     Gemini metering now only exists in `retrieveUserQuota`'s per-model
//     buckets, which the panel reads to keep the Gemini pool visible.
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
    private static let quotaURL = URL(
        string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    )!
    private static let tokenRefreshURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let userAgent = "antigravity-cli"

    /// The two independent quota pools. Each has its own 5h and weekly window, so
    /// a row is identified by pool plus window, never by window alone.
    private static let geminiPool = "aiUsage.pool.gemini"
    private static let otherPool = "aiUsage.pool.other"
    private static let poolOrder = [geminiPool, otherPool]
    private static let windowOrder = ["5h", "7d"]

    private static let oauthClient = OAuthClient(
        id: "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com",
        secret: "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"
    )

    private static let tokenCache = AntigravityTokenCache()
    private static let tableCache = AntigravityTableCache()

    // MARK: - Fetch

    static func fetch() async throws -> ProviderUsageSnapshot {
        let credential = try readCredential()
        let token = try await accessToken(from: credential)

        do {
            return try await fetchQuota(accessToken: token)
        } catch AIUsageError.tokenExpired {
            // The server rejected a token our stored expiry still called valid
            // (revoked early, or `agy` refreshed the item behind us).
            let refreshed = try await refreshAccessToken(credential)
            return try await fetchQuota(accessToken: refreshed)
        }
    }

    /// Clears the in-process token so the next fetch re-reads the Keychain `agy`
    /// wrote. Called on manual retry; the fetch path also self-recovers on 401.
    static func resetCredentialCache() {
        Task { await tokenCache.invalidate() }
    }

    /// Three sources, in the order they help:
    ///
    /// - the group summary is the only body that names a weekly window;
    /// - the per-model body still reports the Gemini pool the summary dropped;
    /// - the CLI's own `/usage` panel is the only place the Gemini **weekly**
    ///   window appears at all. It is a scraper of an undocumented TUI, so it is
    ///   cached and refreshed on a long interval, and every failure simply leaves
    ///   the REST rows in place.
    private static func fetchQuota(accessToken: String) async throws -> ProviderUsageSnapshot {
        let summary = try await fetchSummary(accessToken: accessToken)
        let perModel = (try? await fetchPerModel(accessToken: accessToken)) ?? []
        let scraped = await scrapedWindows()

        let windows = merge(merge(summary.windows, perModel), scraped)
        guard !windows.isEmpty else { return summary }
        return ProviderUsageSnapshot(provider: id, windows: windows, fetchedAt: Date())
    }

    /// The CLI panel's rows, refreshed when the cached set is older than the
    /// probe interval. A warm cache is returned immediately and the scrape runs
    /// behind it, because launching the CLI takes seconds.
    private static func scrapedWindows() async -> [UsageWindow] {
        if let fresh = await tableCache.fresh() { return fresh }

        let stale = await tableCache.lastKnown()
        guard await tableCache.beginRefresh() else { return stale ?? [] }

        if let stale {
            Task.detached { await refreshTable() }
            return stale
        }
        await refreshTable()
        return await tableCache.lastKnown() ?? []
    }

    private static func refreshTable() async {
        do {
            let rows = try await scrapeUsageTable()
            await tableCache.store(rows)
        } catch {
            log.notice("Antigravity /usage probe unavailable: \(error)")
            await tableCache.fail()
        }
    }

    /// Runs `agy -p "/usage"` in a PTY and captures the quota table it paints.
    /// Throws when the CLI is absent or never prints the panel.
    private static func scrapeUsageTable() async throws -> [UsageWindow] {
        guard let binary = CLIBinaryResolver.resolveAntigravityBinary() else {
            throw AIUsageError.endpointNotFound
        }

        let text = try await PTYProbe.capture(
            binary: binary,
            timeout: 75,
            config: PTYProbe.Config(
                arguments: ["-p", "/usage"],
                winsize: Self.ptyWinsize(rows: 40, columns: 120),
                initialDelay: 1,
                command: "",
                pollInterval: 0.3,
                settleDelay: 0.8,
                workDirPrefix: "lightstats-agy-",
                onOutput: { text, _ in
                    let clean = text.lowercased()
                    let complete = clean.contains("weekly limit remaining")
                        && clean.contains("five hour limit remaining")
                    return complete ? .complete : .keepReading
                }
            )
        )

        let rows = parseUsageTable(text)
        guard !rows.isEmpty else { throw AIUsageError.network }
        return rows
    }

    private static func ptyWinsize(rows: UInt16, columns: UInt16) -> winsize {
        winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
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

    private static func fetchPerModel(accessToken: String) async throws -> [UsageWindow] {
        var request = URLRequest(url: quotaURL, timeoutInterval: UsageHTTPClient.defaultTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("{}".utf8)

        return try parseQuota(try await UsageHTTPClient.send(request))
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

        let windows = poolWindows(in: groups)
        guard !windows.isEmpty else { throw AIUsageError.decoding }

        return ProviderUsageSnapshot(provider: id, windows: windows, fetchedAt: Date())
    }

    /// Testable seam (also the live parse path): decode a `retrieveUserQuota`
    /// body with no network. Collapses per-model buckets into one row per model
    /// pool, using the pool's most-consumed bucket.
    ///
    /// This endpoint reports no window kind — every bucket carries only its own
    /// reset, and the reset it reports is the short one (hours away, not days),
    /// so those buckets are the pool's `5h` row. The weekly row comes from the
    /// summary, which is the only body that names a window.
    static func parseQuota(_ data: Data) throws -> [UsageWindow] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = json["buckets"] as? [[String: Any]] else {
            throw AIUsageError.decoding
        }

        var tightest: [String: UsageWindow] = [:]
        for bucket in buckets {
            guard let modelId = bucket["modelId"] as? String,
                  let pool = modelFamily(of: modelId),
                  let remaining = double(bucket["remainingFraction"]),
                  let reset = date(bucket["resetTime"]) else { continue }

            let usedPercent = min(100, max(0, (1 - remaining) * 100))
            guard usedPercent > (tightest[pool]?.usedPercent ?? -1) else { continue }
            tightest[pool] = UsageWindow(
                label: "5h",
                pool: pool,
                usedPercent: usedPercent,
                resetsAt: reset
            )
        }

        return poolOrder.compactMap { tightest[$0] }
    }

    /// Every window that exists gets a row: the two bodies overlap only on the
    /// short window, and each pool meters both of its windows separately. A
    /// repeated window is merged by taking the more-consumed reading, which is
    /// the same value read twice rather than a choice between two answers.
    static func merge(_ summary: [UsageWindow], _ perModel: [UsageWindow]) -> [UsageWindow] {
        var tightest: [String: UsageWindow] = [:]
        for window in summary + perModel {
            guard let used = window.usedPercent else { continue }
            let key = rowKey(pool: window.pool, window: window.label)
            if used > (tightest[key]?.usedPercent ?? -1) {
                tightest[key] = window
            }
        }
        return ordered(tightest)
    }

    /// Pool order, then window order, so a row never moves because a body
    /// happened to list its buckets differently.
    private static func ordered(_ rows: [String: UsageWindow]) -> [UsageWindow] {
        var ordered: [UsageWindow] = []
        for pool in poolOrder {
            for window in windowOrder {
                if let row = rows[rowKey(pool: pool, window: window)] {
                    ordered.append(row)
                }
            }
        }
        return ordered
    }

    private static func rowKey(pool: String?, window: String) -> String {
        "\(pool ?? "")|\(window)"
    }

    /// `gemini-*` and `claude-*`/`gpt-*` are the two model pools; `chat_*`
    /// (assistant chat) and `tab_*` (tab autocomplete) are separate products.
    private static func modelFamily(of modelId: String) -> String? {
        let lower = modelId.lowercased()
        if lower.hasPrefix("gemini") { return geminiPool }
        if lower.hasPrefix("claude") || lower.hasPrefix("gpt") { return otherPool }
        return nil
    }

    /// The body meters one subscription in two independent pools — Gemini and the
    /// third-party models — each with a 5h and a weekly bucket. Every bucket that
    /// names a window is its own row.
    private static func poolWindows(in groups: [[String: Any]]) -> [UsageWindow] {
        var rows: [String: UsageWindow] = [:]

        for group in groups {
            guard let buckets = group["buckets"] as? [[String: Any]],
                  let pool = poolLabel(of: group) else { continue }

            for bucket in buckets {
                guard let window = windowKind(of: bucket),
                      let remaining = double(bucket["remainingFraction"]) else { continue }

                rows[rowKey(pool: pool, window: window)] = UsageWindow(
                    label: window,
                    pool: pool,
                    usedPercent: min(100, max(0, (1 - remaining) * 100)),
                    resetsAt: date(bucket["resetTime"])
                )
            }
        }

        return ordered(rows)
    }

    /// Maps a summary group's `displayName` to its pool. Unknown groups are
    /// skipped rather than labelled with a guess.
    private static func poolLabel(of group: [String: Any]) -> String? {
        guard let displayName = (group["displayName"] as? String)?.lowercased() else { return nil }
        if displayName.contains("gemini") { return geminiPool }
        if displayName.contains("claude") || displayName.contains("gpt") { return otherPool }
        return nil
    }

    /// Recognizes the two metered window kinds; an unrecognized window is
    /// skipped rather than treated as pool data.
    private static func windowKind(of bucket: [String: Any]) -> String? {
        guard let window = (bucket["window"] as? String)?.lowercased() else { return nil }
        switch window {
        case "5h": return "5h"
        case "weekly": return "7d"
        default: return nil
        }
    }

    /// Testable seam: parse the quota table `agy` prints for `/usage`. Rows look
    /// like `Gemini Models  Weekly Limit Remaining  94%  2026-11-02T14:20:34Z`,
    /// separated by tabs or by aligned columns of spaces. The percentage is the
    /// remaining share, which the panel stores as used.
    static func parseUsageTable(_ text: String) -> [UsageWindow] {
        var rows: [String: UsageWindow] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let fields = tableFields(rawLine)
            guard fields.count >= 3,
                  let pool = poolLabel(named: fields[0]),
                  let window = windowKind(named: fields[1]),
                  let percent = firstPercent(in: fields) else { continue }

            let resetsAt = fields.compactMap(tableDate).first
            rows[rowKey(pool: pool, window: window)] = UsageWindow(
                label: window,
                pool: pool,
                usedPercent: min(100, max(0, 100 - percent)),
                resetsAt: resetsAt
            )
        }

        return ordered(rows)
    }

    /// Splits a rendered table row into cells, whether the CLI separated them
    /// with tabs or with runs of spaces for column alignment.
    private static func tableFields(_ line: String) -> [String] {
        let tabSeparated = line.components(separatedBy: "\t")
        let cells = tabSeparated.count > 1
            ? tabSeparated
            : line.components(separatedBy: "  ")
        return cells
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func firstPercent(in fields: [String]) -> Double? {
        for field in fields where field.hasSuffix("%") {
            if let value = Double(field.dropLast()) { return value }
        }
        return nil
    }

    /// The same instant arrives in two shapes: an ISO-8601 stamp with seconds
    /// when the CLI writes to a pipe, and a `yyyy-MM-dd HH:mm` local stamp when
    /// it paints a terminal (which is what the PTY capture sees). The local shape
    /// carries no seconds, so it resolves to the start of that minute.
    private static func tableDate(_ text: String) -> Date? {
        if text.contains("T"), text.hasSuffix("Z") {
            return ISO8601DateFormatter().date(from: text)
        }

        let head = text.split(separator: " ").prefix(2).joined(separator: " ")
        guard head.count == "yyyy-MM-dd HH:mm".count else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: head)
    }

    /// The panel's group name mapped to a pool. Matched case-insensitively on a
    /// substring, because the CLI prints the server's `displayName` verbatim.
    private static func poolLabel(named name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("gemini") { return geminiPool }
        if lower.contains("claude") || lower.contains("gpt") { return otherPool }
        return nil
    }

    /// The panel's bucket label mapped to the row's window kind.
    private static func windowKind(named name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("weekly") { return "7d" }
        if lower.contains("hour") { return "5h" }
        return nil
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
private actor AntigravityTableCache {
    /// The CLI panel changes slowly and takes seconds to launch, so it is read on
    /// this interval rather than on every poll.
    private let interval: TimeInterval = 600
    private var rows: [UsageWindow] = []
    private var fetchedAt: Date?
    private var isRefreshing = false

    func fresh() -> [UsageWindow]? {
        guard let fetchedAt, Date().timeIntervalSince(fetchedAt) < interval, !rows.isEmpty else {
            return nil
        }
        return rows
    }

    func lastKnown() -> [UsageWindow]? {
        rows.isEmpty ? nil : rows
    }

    /// Returns false when a scrape is already running, so concurrent polls do not
    /// each launch the CLI.
    func beginRefresh() -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        return true
    }

    func store(_ rows: [UsageWindow]) {
        self.rows = rows
        fetchedAt = Date()
        isRefreshing = false
    }

    func fail() {
        isRefreshing = false
    }
}

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
