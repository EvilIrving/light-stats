//
//  GrokUsageService.swift
//  Light Stats
//

import Foundation

enum GrokUsageService: UsageProviding {
    static var id: AIProvider { .grok }

    private static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    private static let oidcPrefix = "https://auth.x.ai::"
    private static let legacyScope = "https://accounts.x.ai/sign-in"

    private static let ledgerURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing")!

    static func fetch() async throws -> ProviderUsageSnapshot {
        guard let token = readAccessToken() else {
            throw AIUsageError.credentialsMissing
        }
        let headers = [
            "Authorization": "Bearer \(token)",
            "x-xai-token-auth": "xai-grok-cli",
            "Accept": "application/json"
        ]
        let credits = try await UsageHTTPClient.get(url: billingURL, headers: headers)
        if let root = try? decodeRoot(credits), publishedPercent(root.config) != nil {
            return try snapshot(credits: root, ledger: nil)
        }
        // Unified SuperGrok often omits weekly percent; the monthly ledger still
        // carries used/limit. Try it before treating an omitted 0 as "unknown".
        if let ledger = try? await UsageHTTPClient.get(url: ledgerURL, headers: headers) {
            if let snapshot = try? parseBillingJSON(credits, ledger: ledger) {
                return snapshot
            }
            return try parseBillingJSON(ledger)
        }
        return try parseBillingJSON(credits)
    }

    static func parseBillingJSON(_ data: Data, ledger: Data? = nil, now: Date = Date()) throws -> ProviderUsageSnapshot {
        let credits = try decodeRoot(data)
        let ledgerRoot = ledger.flatMap { try? decodeRoot($0) }
        return try snapshot(credits: credits, ledger: ledgerRoot, now: now)
    }

    static func parseAuthJSON(_ object: [String: Any]) -> String? {
        var oidc: String?
        var legacy: String?
        for (scope, value) in object {
            guard let entry = value as? [String: Any],
                  let key = entry["key"] as? String,
                  !key.isEmpty else { continue }
            if scope.hasPrefix(oidcPrefix) {
                oidc = key
            } else if scope == legacyScope || scope.contains("/sign-in") {
                legacy = key
            }
        }
        return oidc ?? legacy
    }

    private static func readAccessToken() -> String? {
        guard let json = LocalAuthFileReader.readJSON(relativePath: ".grok/auth.json") else {
            return nil
        }
        return parseAuthJSON(json)
    }

    static func shortWindowLabel(until resetsAt: Date?, now: Date = Date()) -> String {
        guard let resetsAt else { return "5h" }
        let hours = resetsAt.timeIntervalSince(now) / 3600
        if hours <= 6 { return "5h" }
        if hours <= 8 * 24 { return "7d" }
        return UsageWindowLabel.month.key
    }

    private static func snapshot(credits: Root, ledger: Root?, now: Date = Date()) throws -> ProviderUsageSnapshot {
        guard let config = credits.config ?? ledger?.config else { throw AIUsageError.decoding }
        let percent: Double?
        let source: Config
        if let published = publishedPercent(credits.config) {
            percent = published
            source = credits.config ?? config
        } else if let published = publishedPercent(ledger?.config) {
            percent = published
            source = ledger?.config ?? config
        } else if let inferred = inferredZeroPercent(credits.config, now: now) {
            percent = inferred
            source = credits.config ?? config
        } else {
            percent = nil
            source = credits.config ?? config
        }

        let resetRaw = source.currentPeriod?.end ?? source.billingPeriodEnd
            ?? config.currentPeriod?.end ?? config.billingPeriodEnd
        let resetsAt = parseISO8601(resetRaw)
        guard percent != nil || resetsAt != nil else { throw AIUsageError.decoding }
        return ProviderUsageSnapshot(
            provider: .grok,
            windows: [
                UsageWindow(
                    label: periodLabel(source.currentPeriod?.type, until: resetsAt, now: now),
                    usedPercent: percent,
                    resetsAt: resetsAt
                )
            ],
            fetchedAt: now
        )
    }

    private static func publishedPercent(_ config: Config?) -> Double? {
        guard let config else { return nil }
        if let published = config.creditUsagePercent, published.isFinite {
            return clampPercent(published)
        }
        if let product = config.productUsage?
            .compactMap(\.usagePercent)
            .first(where: \.isFinite) {
            return clampPercent(product)
        }
        if let cap = config.onDemandCap?.val, cap > 0, let used = config.onDemandUsed?.val {
            return clampPercent(used / cap * 100)
        }
        if let cap = config.monthlyLimit?.val, cap > 0, let used = config.used?.val {
            return clampPercent(used / cap * 100)
        }
        return nil
    }

    /// Proto3 JSON omits default 0.0 for `credit_usage_percent`. A live weekly or
    /// monthly period with no published percent is 0 used — Grok's own billing UI
    /// reads the omitted scalar the same way.
    private static func inferredZeroPercent(_ config: Config?, now: Date) -> Double? {
        guard let config, let period = config.currentPeriod else { return nil }
        let recognized = period.type == "USAGE_PERIOD_TYPE_WEEKLY"
            || period.type == "USAGE_PERIOD_TYPE_MONTHLY"
            || config.isUnifiedBillingUser == true
        guard recognized else { return nil }
        let end = parseISO8601(period.end) ?? parseISO8601(config.billingPeriodEnd)
        guard let end, now <= end else { return nil }
        if let start = parseISO8601(period.start), now < start { return nil }
        return 0
    }

    private static func clampPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func decodeRoot(_ data: Data) throws -> Root {
        do {
            return try JSONDecoder().decode(Root.self, from: data)
        } catch {
            throw AIUsageError.decoding
        }
    }

    private static func periodLabel(_ type: String?, until resetsAt: Date?, now: Date) -> String {
        switch type {
        case "USAGE_PERIOD_TYPE_WEEKLY": return "7d"
        case "USAGE_PERIOD_TYPE_MONTHLY": return UsageWindowLabel.month.key
        default: return shortWindowLabel(until: resetsAt, now: now)
        }
    }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        let optionSets: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone],
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime, .withColonSeparatorInTimeZone],
            [.withInternetDateTime]
        ]
        for options in optionSets {
            formatter.formatOptions = options
            if let date = formatter.date(from: raw) { return date }
        }
        return formatter.date(from: raw.replacingOccurrences(of: "+00:00", with: "Z"))
    }

    private struct Root: Decodable {
        let config: Config?
    }

    private struct Config: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: Period?
        let billingPeriodEnd: String?
        let onDemandCap: Amount?
        let onDemandUsed: Amount?
        let monthlyLimit: Amount?
        let used: Amount?
        let isUnifiedBillingUser: Bool?
        let productUsage: [ProductUsage]?
    }

    private struct Period: Decodable {
        let type: String?
        let start: String?
        let end: String?
    }

    private struct ProductUsage: Decodable {
        let product: String?
        let usagePercent: Double?
    }

    private struct Amount: Decodable {
        let val: Double?
    }
}
