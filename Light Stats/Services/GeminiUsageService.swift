//
//  GeminiUsageService.swift
//  Light Stats
//
//  Created on 2026/06/17.
//

import Foundation

/// Fetches Gemini CLI quota usage using local OAuth credentials.
/// Credentials are maintained by Gemini CLI in ~/.gemini/oauth_creds.json; we only read and refresh them.
///
/// Adds curl fallback for URLSession timeouts — Google Cloud APIs occasionally
/// trigger NSURLErrorTimedOut on slow connections; retrying via /usr/bin/curl
/// often succeeds (CodexBar pattern).
nonisolated enum GeminiUsageService {

    private static let quotaURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
    private static let loadCodeAssistURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    private static let tokenRefreshURL = URL(string: "https://oauth2.googleapis.com/token")!

    private static var credentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
    }

    private static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/settings.json")
    }

    private struct Credentials {
        var accessToken: String?
        var refreshToken: String?
        var idToken: String?
        var expiryDate: Date?
        var rawJSON: [String: Any]
    }

    private struct OAuthClient {
        let clientId: String
        let clientSecret: String
    }

    // MARK: - Fetch

    static func fetch() async throws -> ProviderUsageSnapshot {
        try validateAuthType()

        var credentials = try loadCredentials()
        let token = try await validAccessToken(from: &credentials)
        let projectId = try? await loadCodeAssistProjectId(accessToken: token)
        let snapshot = try await fetchQuota(accessToken: token, projectId: projectId)

        return snapshot
    }

    private static func validateAuthType() throws {
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let security = json["security"] as? [String: Any],
              let auth = security["auth"] as? [String: Any],
              let selectedType = auth["selectedType"] as? String else {
            return
        }

        if selectedType == "api-key" || selectedType == "vertex-ai" {
            throw AIUsageError.credentialsMissing
        }
    }

    private static func validAccessToken(from credentials: inout Credentials) async throws -> String {
        if let token = credentials.accessToken,
           !token.isEmpty,
           credentials.expiryDate.map({ $0 > Date().addingTimeInterval(60) }) != false {
            return token
        }

        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw AIUsageError.tokenExpired
        }
        guard let client = findOAuthClient() else {
            throw AIUsageError.tokenExpired
        }

        return try await refreshAccessToken(refreshToken: refreshToken, client: client, credentials: &credentials)
    }

    private static func fetchQuota(accessToken: String, projectId: String?) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: quotaURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let projectId, !projectId.isEmpty {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["project": projectId])
        } else {
            request.httpBody = Data("{}".utf8)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await fetchWithCurlFallback(request)
        } catch {
            throw AIUsageError.network
        }

        guard let http = response as? HTTPURLResponse else { throw AIUsageError.network }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AIUsageError.tokenExpired
        }
        guard (200..<300).contains(http.statusCode) else { throw AIUsageError.network }

        return try parseQuotaResponse(data)
    }

    /// Attempts the request with URLSession; on timeout, retries with /usr/bin/curl.
    /// Google Cloud APIs sometimes trigger NSURLErrorTimedOut spuriously on macOS;
    /// curl often succeeds on the same network (CodexBar pattern).
    private static func fetchWithCurlFallback(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            guard isTimeoutError(error) else { throw error }
            return try await curlFetch(request)
        }
    }

    private static func isTimeoutError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    private static func curlFetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw AIUsageError.network
        }

        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
            .appendingPathComponent("lightstats-gemini-curl-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let configURL = tmpDir.appendingPathComponent("curl.conf")
        var config: [String] = [
            "silent",
            "show-error",
            "location",
            "url = \"\(url.absoluteString)\"",
            "max-time = \(max(1, Int(ceil(request.timeoutInterval))))",
        ]

        if let method = request.httpMethod, !method.isEmpty {
            config.append("request = \"\(method)\"")
        }

        for (name, value) in (request.allHTTPHeaderFields ?? [:]) {
            config.append("header = \"\(name): \(value)\"")
        }

        if let body = request.httpBody {
            let bodyURL = tmpDir.appendingPathComponent("body")
            try body.write(to: bodyURL)
            config.append("data-binary = \"@\(bodyURL.path)\"")
        }

        let marker = "__LIGHTSTATS_HTTP_STATUS__"
        config.append("write-out = \"\(marker)%{http_code}\"")

        try config.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["--config", configURL.path]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else {
            throw AIUsageError.network
        }
        process.waitUntilExit()

        let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8),
              let markerRange = output.range(of: marker, options: .backwards) else {
            throw AIUsageError.network
        }

        let bodyText = String(output[..<markerRange.lowerBound])
        let statusText = output[markerRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let statusCode = Int(statusText),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: nil,
                  headerFields: nil) else {
            throw AIUsageError.network
        }

        return (Data(bodyText.utf8), response)
    }

    private static func loadCodeAssistProjectId(accessToken: String) async throws -> String? {
        var request = URLRequest(url: loadCodeAssistURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"metadata\":{\"ideType\":\"GEMINI_CLI\",\"pluginType\":\"GEMINI\"}}".utf8)

        let (data, response) = try await fetchWithCurlFallback(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let project = json["cloudaicompanionProject"] as? String {
            return project.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let project = json["cloudaicompanionProject"] as? [String: Any] {
            return (project["projectId"] as? String) ?? (project["id"] as? String)
        }
        return nil
    }

    // MARK: - Credentials

    private static func loadCredentials() throws -> Credentials {
        guard let data = try? Data(contentsOf: credentialsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.credentialsMissing
        }

        return Credentials(
            accessToken: json["access_token"] as? String,
            refreshToken: json["refresh_token"] as? String,
            idToken: json["id_token"] as? String,
            expiryDate: expiryDate(from: json["expiry_date"]),
            rawJSON: json
        )
    }

    private static func refreshAccessToken(
        refreshToken: String,
        client: OAuthClient,
        credentials: inout Credentials
    ) async throws -> String {
        var request = URLRequest(url: tokenRefreshURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": client.clientId,
            "client_secret": client.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = formURLEncoded(form).data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await fetchWithCurlFallback(request)
        } catch {
            throw AIUsageError.network
        }

        guard let http = response as? HTTPURLResponse else { throw AIUsageError.network }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AIUsageError.tokenExpired
        }
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              !accessToken.isEmpty else {
            throw AIUsageError.decoding
        }

        credentials.accessToken = accessToken
        credentials.rawJSON["access_token"] = accessToken
        if let idToken = json["id_token"] as? String {
            credentials.idToken = idToken
            credentials.rawJSON["id_token"] = idToken
        }
        if let expiresIn = json["expires_in"] as? Double {
            let expiry = Date().addingTimeInterval(expiresIn)
            credentials.expiryDate = expiry
            credentials.rawJSON["expiry_date"] = Int(expiry.timeIntervalSince1970 * 1000)
        }
        persist(credentials)

        return accessToken
    }

    private static func persist(_ credentials: Credentials) {
        guard let data = try? JSONSerialization.data(withJSONObject: credentials.rawJSON, options: [.prettyPrinted]) else {
            return
        }
        try? data.write(to: credentialsURL, options: [.atomic])
    }

    // MARK: - OAuth client discovery

    private static func findOAuthClient() -> OAuthClient? {
        for path in possibleOAuthClientFiles() {
            guard let source = try? String(contentsOfFile: path, encoding: .utf8),
                  let client = parseOAuthClient(from: source) else {
                continue
            }
            return client
        }
        return nil
    }

    private static func possibleOAuthClientFiles() -> [String] {
        let binaryPaths = possibleGeminiBinaries()
        var files: [String] = []

        for binaryPath in binaryPaths {
            let resolved = URL(fileURLWithPath: binaryPath).resolvingSymlinksInPath().path
            let root = (resolved as NSString).deletingLastPathComponent
            files.append(root + "/../lib/node_modules/@google/gemini-cli/" + oauthClientRelativePath)
            files.append(root + "/../libexec/lib/node_modules/@google/gemini-cli/" + oauthClientRelativePath)
            files.append(root + "/../node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js")
        }

        return Array(Set(files.map { URL(fileURLWithPath: $0).standardizedFileURL.path }))
    }

    private static let oauthClientRelativePath = "node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"

    private static func possibleGeminiBinaries() -> [String] {
        var paths = ["/opt/homebrew/bin/gemini", "/usr/local/bin/gemini"]
        let pathValues = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        paths.append(contentsOf: pathValues.map { $0 + "/gemini" })
        return paths.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func parseOAuthClient(from source: String) -> OAuthClient? {
        guard let id = firstRegexMatch(#"OAUTH_CLIENT_ID[^"']*["']([^"']+)["']"#, in: source),
              let secret = firstRegexMatch(#"OAUTH_CLIENT_SECRET[^"']*["']([^"']+)["']"#, in: source) else {
            return nil
        }
        return OAuthClient(clientId: id, clientSecret: secret)
    }

    // MARK: - Parsing

    private struct ModelQuota {
        let modelId: String
        let percentLeft: Double
        let resetTime: Date?
    }

    private static func parseQuotaResponse(_ data: Data) throws -> ProviderUsageSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw AIUsageError.decoding
        }

        let quotas = collectQuotas(from: json)
        guard !quotas.isEmpty else { throw AIUsageError.decoding }

        let windows = usageWindows(from: quotas)
        guard !windows.isEmpty else { throw AIUsageError.decoding }

        return ProviderUsageSnapshot(provider: .gemini, windows: windows, fetchedAt: Date())
    }

    private static func collectQuotas(from value: Any) -> [ModelQuota] {
        if let array = value as? [Any] {
            return array.flatMap(collectQuotas)
        }

        guard let dictionary = value as? [String: Any] else { return [] }
        var quotas = dictionary.values.flatMap(collectQuotas)

        if let remaining = doubleValue(dictionary["remainingFraction"]),
           let modelId = stringValue(dictionary["modelId"] ?? dictionary["model"] ?? dictionary["name"]) {
            quotas.append(ModelQuota(
                modelId: modelId,
                percentLeft: max(0, min(100, remaining * 100)),
                resetTime: dateValue(dictionary["resetTime"] ?? dictionary["reset_time"])
            ))
        }

        return quotas
    }

    private static func usageWindows(from quotas: [ModelQuota]) -> [UsageWindow] {
        let lower = quotas.map { ($0.modelId.lowercased(), $0) }
        var windows: [UsageWindow] = []

        if let pro = lowestRemaining(in: lower.filter({ $0.0.contains("pro") }).map(\.1)) {
            windows.append(window(label: "Pro", quota: pro))
        }
        let flashQuotas = lower.filter { $0.0.contains("flash") && !$0.0.contains("flash-lite") }.map(\.1)
        if let flash = lowestRemaining(in: flashQuotas) {
            windows.append(window(label: "Flash", quota: flash))
        }
        if let lite = lowestRemaining(in: lower.filter({ $0.0.contains("flash-lite") }).map(\.1)) {
            windows.append(window(label: "Lite", quota: lite))
        }
        if windows.isEmpty, let lowest = lowestRemaining(in: quotas) {
            windows.append(window(label: "Gemini", quota: lowest))
        }

        return windows
    }

    private static func lowestRemaining(in quotas: [ModelQuota]) -> ModelQuota? {
        quotas.min { $0.percentLeft < $1.percentLeft }
    }

    private static func window(label: String, quota: ModelQuota) -> UsageWindow {
        UsageWindow(label: label, usedPercent: 100 - quota.percentLeft, resetsAt: quota.resetTime)
    }

    private static func expiryDate(from value: Any?) -> Date? {
        guard let value else { return nil }
        if let double = doubleValue(value) {
            return Date(timeIntervalSince1970: double > 10_000_000_000 ? double / 1_000 : double)
        }
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        if let double = doubleValue(value) {
            return Date(timeIntervalSince1970: double > 10_000_000_000 ? double / 1_000 : double)
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    private static func formURLEncoded(_ values: [String: String]) -> String {
        values.map { key, value in
            "\(urlEncode(key))=\(urlEncode(value))"
        }
        .joined(separator: "&")
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static func firstRegexMatch(_ pattern: String, in source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[range])
    }
}
