//
//  WarpUsageService.swift
//  Light Stats
//

import Foundation

enum WarpUsageService: UsageProviding {
    static var id: AIProvider { .warp }

    private static let endpoint = URL(string: "https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo")!
    private static let query = """
    query GetRequestLimitInfo { \
      user { requestLimitInfo { \
        isUnlimited requestLimit requestsUsedSinceLastRefresh nextRefreshTime \
      } } \
    }
    """

    static func fetch() async throws -> ProviderUsageSnapshot {
        let token = try await KeychainCredentialWriter.loadToken(for: .warp)
        var request = URLRequest(url: endpoint, timeoutInterval: UsageHTTPClient.defaultTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await UsageHTTPClient.send(request)
        return try parseGraphQLJSON(data)
    }

    static func parseGraphQLJSON(_ data: Data) throws -> ProviderUsageSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.decoding
        }
        if object["errors"] is [Any] { throw AIUsageError.decoding }
        guard let info = findLimitInfo(object) else { throw AIUsageError.decoding }

        if bool(info["isUnlimited"]) == true {
            return ProviderUsageSnapshot(
                provider: .warp,
                windows: [UsageWindow(label: .quota, usedPercent: 0, resetsAt: JSONValueReader.date(info["nextRefreshTime"]))],
                fetchedAt: Date()
            )
        }

        let used = JSONValueReader.double(info["requestsUsedSinceLastRefresh"])
        let limit = JSONValueReader.double(info["requestLimit"])
        guard let used, let limit, limit > 0 else { throw AIUsageError.decoding }
        let percent = min(100, max(0, used / limit * 100))
        return ProviderUsageSnapshot(
            provider: .warp,
            windows: [UsageWindow(label: .quota, usedPercent: percent, resetsAt: JSONValueReader.date(info["nextRefreshTime"]))],
            fetchedAt: Date()
        )
    }

    private static func findLimitInfo(_ object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if dict["requestLimit"] != nil || dict["requestsUsedSinceLastRefresh"] != nil {
                return dict
            }
            for value in dict.values {
                if let found = findLimitInfo(value) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = findLimitInfo(value) { return found }
            }
        }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        value as? Bool
    }
}
