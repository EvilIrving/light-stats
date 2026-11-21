//
//  CursorUsageService.swift
//  Light Stats
//
//  Reads Cursor.app's own session from its VS Code-style `state.vscdb` and asks
//  Cursor's dashboard for the current period usage. Two measured facts shape
//  this file:
//
//  1. The session moved. `cursorAuth/accessToken` is no longer a plaintext JWT:
//     since Cursor 3.27 it is `cursor-safe-storage:v1:` plus ciphertext keyed by
//     `Cursor Safe Storage` in the login keychain (`CursorSafeStorage`).
//  2. The endpoint moved with it. The web page's `/api/usage-summary` is driven
//     by the `WorkosCursorSessionToken` cookie, which is built from the JWT's
//     `sub` claim — a plaintext-only arrangement. The dashboard's own RPC takes
//     the token as a bearer and returns the same numbers, so the app's
//     credential is all that is needed and no cookie is built.
//
//  `GetCurrentPeriodUsage` reports totals; `GetPlanInfo` says which allowance the
//  account is metered on. A unified plan reports one weekly included allowance
//  (a single meter). An older plan reports separate Cursor-Models and
//  Other-Models bags against a monthly billing cycle.
//

import Foundation
import SQLite3

enum CursorUsageService: UsageProviding {
    static var id: AIProvider { .cursor }

    private static let log = AppLogger(category: "CursorUsage")

    private static let dashboardURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/")!
    private static let periodUsageMethod = "GetCurrentPeriodUsage"
    private static let planInfoMethod = "GetPlanInfo"
    private static let tokenKey = "cursorAuth/accessToken"

    private static let credentialCache = CursorCredentialCache()

    // MARK: - Fetch

    static func fetch() async throws -> ProviderUsageSnapshot {
        let token = try accessToken()
        async let periodUsage = fetchPeriodUsage(token: token)
        async let planInfo = fetchPlanInfo(token: token)
        return try parsePeriodUsage(try await periodUsage, planInfo: await planInfo)
    }

    /// Drops the decrypted token so the next fetch re-reads the database and, if
    /// the value is still ciphertext, the keychain. Called on manual retry.
    static func resetCredentialCache() {
        credentialCache.invalidate()
    }

    private static func fetchPeriodUsage(token: String) async throws -> Data {
        try await UsageHTTPClient.post(dashboardRequest(periodUsageMethod, token: token))
    }

    /// Best effort: without it the account is read as a monthly one, which is what
    /// every plan before the unified allowance was.
    private static func fetchPlanInfo(token: String) async -> Data? {
        try? await UsageHTTPClient.post(dashboardRequest(planInfoMethod, token: token))
    }

    /// A Connect call: an empty JSON message, and the protocol version header the
    /// server requires next to the bearer token.
    private static func dashboardRequest(_ method: String, token: String) -> URLRequest {
        var request = URLRequest(
            url: dashboardURL.appendingPathComponent(method),
            timeoutInterval: UsageHTTPClient.defaultTimeout
        )
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Light Stats", forHTTPHeaderField: "User-Agent")
        return request
    }

    // MARK: - Parsing

    /// Turns the two dashboard bodies into the panel's windows.
    static func parsePeriodUsage(
        _ periodUsage: Data,
        planInfo: Data?,
        fetchedAt: Date = Date()
    ) throws -> ProviderUsageSnapshot {
        let usage: PeriodUsage
        do {
            usage = try JSONDecoder().decode(PeriodUsage.self, from: periodUsage)
        } catch {
            throw AIUsageError.decoding
        }
        guard let plan = usage.planUsage, plan.hasReading else { throw AIUsageError.decoding }
        let info = planInfo.flatMap { try? JSONDecoder().decode(PlanInfo.self, from: $0) }
        let period = info?.planInfo?.includedUsagePeriod
        let billingCycleEnd = usage.billingCycleEnd?.date ?? info?.planInfo?.billingCycleEnd?.date

        let windows: [UsageWindow]
        if info?.isMerged == true || period == .weekly {
            guard let total = plan.totalPercentUsed else { throw AIUsageError.decoding }
            windows = [UsageWindow(
                label: .usage,
                usedPercent: clamp(total),
                resetsAt: info?.planInfo?.includedUsageResetsAt?.date ?? billingCycleEnd
            )]
        } else {
            windows = [
                plan.totalPercentUsed.map {
                    UsageWindow(label: .usage, usedPercent: clamp($0), resetsAt: billingCycleEnd)
                },
                plan.autoPercentUsed.map {
                    UsageWindow(label: cursorModelsLabel, usedPercent: clamp($0), resetsAt: billingCycleEnd)
                },
                plan.apiPercentUsed.map {
                    UsageWindow(label: otherModelsLabel, usedPercent: clamp($0), resetsAt: billingCycleEnd)
                }
            ].compactMap { $0 }
        }
        guard !windows.isEmpty else { throw AIUsageError.decoding }
        return ProviderUsageSnapshot(provider: .cursor, windows: windows, fetchedAt: fetchedAt)
    }

    /// Cursor's own names for the two monthly bags, as its dashboard shows them.
    private static let cursorModelsLabel = "Cursor"
    private static let otherModelsLabel = "API"

    // MARK: - Credential

    /// The session as Cursor stored it: a plaintext JWT from a build before 3.27,
    /// or `cursor-safe-storage:v1:` ciphertext from every build since.
    private static func accessToken() throws -> String {
        let stored = try readStoredToken()
        if !CursorSafeStorage.isEncrypted(stored) {
            try ensureUsable(stored)
            return stored
        }
        if let cached = credentialCache.token(for: stored) { return cached }
        let token = try decrypt(stored)
        try ensureUsable(token)
        credentialCache.store(token, for: stored)
        return token
    }

    /// Checks the format before asking the keychain for anything: a value this
    /// build cannot decrypt is not worth a system dialog.
    private static func decrypt(_ stored: String) throws -> String {
        guard let ciphertext = CursorSafeStorage.ciphertext(of: stored) else {
            log.error("Cursor session has an unsupported safeStorage format")
            throw AIUsageError.decoding
        }
        // A refusal is remembered for the session: otherwise every refresh would put
        // the same dialog back in front of the user. Only a manual retry re-asks.
        guard !credentialCache.accessRefused else { throw AIUsageError.keychainAccessDenied }
        switch CursorSafeStorage.keychainPasswords() {
        case .passwords(let passwords):
            for password in passwords {
                if let token = CursorSafeStorage.accessToken(decrypting: ciphertext, password: password) {
                    return token
                }
            }
            log.error("Cursor session did not decrypt with any of \(passwords.count) safeStorage keys")
            throw AIUsageError.decoding
        case .denied:
            log.notice("Cursor safeStorage key was refused in the keychain")
            credentialCache.refuseAccess()
            throw AIUsageError.keychainAccessDenied
        case .unavailable(let status):
            // The status is the only thing that separates "Cursor never wrote this"
            // from "we looked in the wrong keychain", and OSLog redacts the message.
            log.error("Cursor safeStorage key is not readable (OSStatus \(status))")
            DiagnosticLogService.recordProbe(
                component: "CursorSafeStorage",
                operation: "keychainPassword",
                status: .unavailable,
                reasonCode: "osStatus\(status)",
                source: "Security/SecItemCopyMatching"
            )
            throw AIUsageError.credentialsMissing
        }
    }

    static func decodeSQLiteValue(_ data: Data, type: Int32) -> String? {
        if type == SQLITE_TEXT {
            return String(data: data, encoding: .utf8)
        }
        if type == SQLITE_BLOB {
            if data.count.isMultiple(of: 2),
               stride(from: 0, to: data.count, by: 2).allSatisfy({
                   (1..<128).contains(data[$0]) && data[$0 + 1] == 0
               }),
               let decoded = String(data: data, encoding: .utf16LittleEndian),
               !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return decoded
            }
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16LittleEndian)
        }
        return nil
    }

    static func databaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(
            "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        )
    }

    private static func readStoredToken() throws -> String {
        let url = databaseURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AIUsageError.credentialsMissing
        }
        do {
            if let token = try queryToken(at: url, immutable: false) {
                return token
            }
        } catch AIUsageError.network {
            if walSidecarsMissing(at: url),
               let token = try? queryToken(at: url, immutable: true) {
                return token
            }
            throw AIUsageError.network
        }
        throw AIUsageError.credentialsMissing
    }

    private static func queryToken(at url: URL, immutable: Bool) throws -> String? {
        var db: OpaquePointer?
        let filename = immutable ? "\(url.absoluteURL.absoluteString)?immutable=1" : url.path
        var flags = SQLITE_OPEN_READONLY
        if immutable { flags |= SQLITE_OPEN_URI }
        let opened = sqlite3_open_v2(filename, &db, flags, nil)
        guard opened == SQLITE_OK else {
            sqlite3_close(db)
            throw AIUsageError.network
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw AIUsageError.network
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, tokenKey, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        let step = sqlite3_step(stmt)
        guard step == SQLITE_ROW else {
            if step == SQLITE_DONE { return nil }
            throw AIUsageError.network
        }
        let type = sqlite3_column_type(stmt, 0)
        let byteCount = Int(sqlite3_column_bytes(stmt, 0))
        let data: Data
        if type == SQLITE_TEXT, let pointer = sqlite3_column_text(stmt, 0) {
            data = Data(bytes: pointer, count: byteCount)
        } else if type == SQLITE_BLOB, let pointer = sqlite3_column_blob(stmt, 0) {
            data = Data(bytes: pointer, count: byteCount)
        } else {
            return nil
        }
        let token = decodeSQLiteValue(data, type: type)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty == false) ? token : nil
    }

    private static func walSidecarsMissing(at url: URL) -> Bool {
        let wal = url.path + "-wal"
        let shm = url.path + "-shm"
        return !FileManager.default.fileExists(atPath: wal)
            && !FileManager.default.fileExists(atPath: shm)
    }

    private static func ensureUsable(_ jwt: String) throws {
        let payload = try jwtPayload(jwt)
        guard let exp = jsonNumber(payload["exp"]) else { return }
        if Date(timeIntervalSince1970: exp).timeIntervalSinceNow <= 60 {
            throw AIUsageError.tokenExpired
        }
    }

    private static func jwtPayload(_ jwt: String) throws -> [String: Any] {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { throw AIUsageError.decoding }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.decoding
        }
        return json
    }

    private static func jsonNumber(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    // MARK: - Response shapes

    private struct PeriodUsage: Decodable {
        let billingCycleEnd: Milliseconds?
        let planUsage: PlanUsage?
    }

    private struct PlanUsage: Decodable {
        let totalPercentUsed: Double?
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?

        var hasReading: Bool {
            totalPercentUsed != nil || autoPercentUsed != nil || apiPercentUsed != nil
        }
    }

    private struct PlanInfo: Decodable {
        let isMerged: Bool?
        let planInfo: Plan?
    }

    private struct Plan: Decodable {
        let includedUsagePeriod: IncludedUsagePeriod?
        let includedUsageResetsAt: Milliseconds?
        let billingCycleEnd: Milliseconds?
    }

    /// The dashboard sends the enum as its name or its number, depending on the
    /// build; unspecified is a monthly cycle.
    private enum IncludedUsagePeriod: Decodable {
        case monthly
        case weekly

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let number = try? value.decode(Int.self) {
                switch number {
                case 2: self = .weekly
                case 0, 1: self = .monthly
                default: throw DecodingError.dataCorruptedError(
                    in: value,
                    debugDescription: "Unknown included-usage period"
                )
                }
                return
            }
            switch try value.decode(String.self) {
            case "INCLUDED_USAGE_PERIOD_WEEKLY": self = .weekly
            case "INCLUDED_USAGE_PERIOD_MONTHLY", "INCLUDED_USAGE_PERIOD_UNSPECIFIED": self = .monthly
            default: throw DecodingError.dataCorruptedError(
                in: value,
                debugDescription: "Unknown included-usage period"
            )
            }
        }
    }

    /// Epoch milliseconds, which the dashboard sends as a string on some builds and
    /// as a number on others.
    private struct Milliseconds: Decodable {
        let value: Int64

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int64.self) {
                value = number
                return
            }
            guard let number = Int64(try container.decode(String.self)) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not an epoch millisecond value"
                )
            }
            value = number
        }

        var date: Date? {
            guard value > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(value) / 1000)
        }
    }
}

// MARK: - Credential cache

/// The decrypted token, keyed by the ciphertext it came from. A poll after the
/// first keychain grant costs nothing, and a user who answered "Allow" instead of
/// "Always Allow" is not asked again on every refresh. A new sign-in changes the
/// stored value and therefore misses the cache.
nonisolated private final class CursorCredentialCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entry: (stored: String, token: String)?
    private var refused = false

    func token(for stored: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry, entry.stored == stored else { return nil }
        return entry.token
    }

    func store(_ token: String, for stored: String) {
        lock.lock()
        defer { lock.unlock() }
        entry = (stored, token)
        refused = false
    }

    /// Whether the user turned down the keychain prompt in this session.
    var accessRefused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return refused
    }

    func refuseAccess() {
        lock.lock()
        defer { lock.unlock() }
        refused = true
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        entry = nil
        refused = false
    }
}
