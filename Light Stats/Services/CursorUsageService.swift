//
//  CursorUsageService.swift
//  Light Stats
//
//  Reads Cursor.app's VS Code-style state.vscdb (cursorAuth/accessToken) and
//  calls cursor.com/api/usage-summary. No browser cookies.
//

import Foundation
import SQLite3

enum CursorUsageService: UsageProviding {
    static var id: AIProvider { .cursor }

    private static let summaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    private static let tokenKey = "cursorAuth/accessToken"

    static func fetch() async throws -> ProviderUsageSnapshot {
        let token = try readAccessToken()
        try ensureUsable(token)
        let cookie = try cookieHeader(for: token)
        let data = try await UsageHTTPClient.get(
            url: summaryURL,
            headers: [
                "Accept": "application/json",
                "Cookie": cookie,
                "User-Agent": "Light Stats"
            ]
        )
        return try parseSummaryJSON(data)
    }

    static func parseSummaryJSON(_ data: Data) throws -> ProviderUsageSnapshot {
        let summary: Summary
        do {
            summary = try JSONDecoder().decode(Summary.self, from: data)
        } catch {
            throw AIUsageError.decoding
        }
        let plan = summary.individualUsage?.plan
        var windows: [UsageWindow] = []
        let reset = parseISO8601(summary.billingCycleEnd)
        if let total = plan?.totalPercentUsed {
            windows.append(UsageWindow(label: .usage, usedPercent: clamp(total), resetsAt: reset))
        } else if let used = plan?.used, let limit = plan?.limit, limit > 0 {
            windows.append(UsageWindow(
                label: .usage,
                usedPercent: clamp(Double(used) / Double(limit) * 100),
                resetsAt: reset
            ))
        }
        if let auto = plan?.autoPercentUsed {
            windows.append(UsageWindow(label: "Auto", usedPercent: clamp(auto), resetsAt: reset))
        }
        if let api = plan?.apiPercentUsed, api > 0 {
            windows.append(UsageWindow(label: "API", usedPercent: clamp(api), resetsAt: reset))
        }
        if let onDemand = summary.individualUsage?.onDemand,
           onDemand.enabled == true,
           let used = onDemand.used,
           let limit = onDemand.limit,
           limit > 0 {
            windows.append(UsageWindow(
                label: .overage,
                usedPercent: clamp(Double(used) / Double(limit) * 100),
                resetsAt: reset
            ))
        }
        if windows.isEmpty { throw AIUsageError.decoding }
        return ProviderUsageSnapshot(provider: .cursor, windows: windows, fetchedAt: Date())
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

    static func cookieHeader(for jwt: String) throws -> String {
        let userID = try userID(from: jwt)
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(jwt)"
    }

    static func databaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(
            "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        )
    }

    private static func readAccessToken() throws -> String {
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

    private static func userID(from jwt: String) throws -> String {
        let payload = try jwtPayload(jwt)
        guard let subject = payload["sub"] as? String,
              let userID = subject.split(separator: "|", omittingEmptySubsequences: true).last.map(String.init),
              !userID.isEmpty else {
            throw AIUsageError.decoding
        }
        return userID
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

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private struct Summary: Decodable {
        let billingCycleEnd: String?
        let individualUsage: Individual?
    }

    private struct Individual: Decodable {
        let plan: Plan?
        let onDemand: OnDemand?
    }

    private struct Plan: Decodable {
        let used: Int?
        let limit: Int?
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
        let totalPercentUsed: Double?
    }

    private struct OnDemand: Decodable {
        let enabled: Bool?
        let used: Int?
        let limit: Int?
    }
}
