//
//  UsageHTTPClient.swift
//  Light Stats
//

import Foundation

/// Shared HTTP for new usage providers. Does not log bodies or headers (tokens).
enum UsageHTTPClient {
    nonisolated static let defaultTimeout: TimeInterval = 15

    static func send(_ request: URLRequest) async throws -> Data {
        // Usage numbers must never come from the shared URL cache — a cached
        // GET would show stale quota until the cache entry expires.
        var request = request
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIUsageError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIUsageError.network
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw AIUsageError.tokenExpired
        case 404:
            throw AIUsageError.endpointNotFound
        default:
            throw AIUsageError.network
        }
    }

    static func get(
        url: URL,
        headers: [String: String],
        timeout: TimeInterval = defaultTimeout
    ) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await send(request)
    }
}
