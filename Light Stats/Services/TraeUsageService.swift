//
//  TraeUsageService.swift
//  Light Stats
//

import Foundation

enum TraeUsageService: UsageProviding {
    static var id: AIProvider { .trae }

    private static let entitlementURL = URL(string: "https://api.trae.cn/trae/api/v2/pay/user_current_entitlement_list")!
    private static let deviceIdKey = "ai.usage.trae.deviceId"

    static func fetch() async throws -> ProviderUsageSnapshot {
        let token = try await KeychainCredentialWriter.loadToken(for: .trae)
        var request = URLRequest(url: entitlementURL, timeoutInterval: UsageHTTPClient.defaultTimeout)
        request.httpMethod = "POST"
        request.setValue("Cloud-IDE-JWT \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("cn", forHTTPHeaderField: "X-User-Region")
        request.setValue(deviceId(), forHTTPHeaderField: "x-device-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let data = try await UsageHTTPClient.send(request)
        return try parseEntitlementJSON(data)
    }

    static func parseEntitlementJSON(_ data: Data) throws -> ProviderUsageSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.decoding
        }
        let packs = array(object["user_entitlement_pack_list"])
            ?? array(dictionary(object["data"])?["user_entitlement_pack_list"])
            ?? []
        var limitTotal: Double = 0
        var usedTotal: Double = 0
        for pack in packs {
            guard let dict = pack as? [String: Any] else { continue }
            let info = dictionary(dict["entitlement_base_info"]) ?? [:]
            let quota = dictionary(info["quota"]) ?? [:]
            let usage = dictionary(dict["usage"]) ?? [:]
            let limit = JSONValueReader.double(quota["credits_limit"]) ?? 0
            let used = max(0, JSONValueReader.double(usage["credits_amount"]) ?? 0)
            if limit > 0 {
                limitTotal += limit
                usedTotal += min(used, limit)
            }
        }
        guard limitTotal > 0 else { throw AIUsageError.decoding }
        let percent = min(100, max(0, usedTotal / limitTotal * 100))
        return ProviderUsageSnapshot(
            provider: .trae,
            windows: [UsageWindow(label: .quota, usedPercent: percent, resetsAt: nil)],
            fetchedAt: Date()
        )
    }

    static func deviceId(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: deviceIdKey),
           existing.count == 16,
           existing.allSatisfy(\.isNumber) {
            return existing
        }
        let generated = (0..<16).map { _ in String(Int.random(in: 0...9)) }.joined()
        defaults.set(generated, forKey: deviceIdKey)
        return generated
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }
}
