//
//  ExitNodeService.swift
//  Light Stats
//
//  公网出口节点探测：向所选 geo-IP 服务发请求拿公网 IP 与归属地。
//  默认关闭，仅在设置开启时被调用。带缓存、超时、静默降级。
//

import Foundation

/// 出口探测使用的 geo-IP 服务。`String` 背书以便存进 UserDefaults。
/// 纯数据枚举标 `nonisolated`，`endpoint` 等成员可在采集 actor 上访问。
nonisolated enum ExitNodeProvider: String, CaseIterable, Sendable {
    case ipsb       // api.ip.sb/geoip（https，无需 key）
    case ipapi      // ip-api.com（http，有频率限制）
    case ipinfo     // ipinfo.io（https，部分字段需 token）

    var displayName: String {
        switch self {
        case .ipsb: return "ip.sb"
        case .ipapi: return "ip-api.com"
        case .ipinfo: return "ipinfo.io"
        }
    }

    var endpoint: URL {
        switch self {
        case .ipsb:
            return URL(string: "https://api.ip.sb/geoip")!
        case .ipapi:
            return URL(string: "http://ip-api.com/json/?fields=status,country,countryCode,city,isp,org,as,query,hosting")!
        case .ipinfo:
            return URL(string: "https://ipinfo.io/json")!
        }
    }
}

/// 出口节点探测服务。actor 隔离，结果回 `@MainActor` 再绑定视图。
actor ExitNodeService {

    /// 上次成功的探测结果，作为缓存与失败回退用。
    private var cached: ExitNode?

    /// 短超时、忽略缓存的会话，避免卡 UI、避免脏数据。
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// 取出口节点。`cacheTTL` 内直接返回缓存，不发请求；失败静默回退到旧缓存（可能为 nil）。
    func fetch(provider: ExitNodeProvider, cacheTTL: TimeInterval) async -> ExitNode? {
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached
        }
        guard let node = await query(provider: provider) else {
            return cached
        }
        cached = node
        return node
    }

    // MARK: - 请求

    private func query(provider: ExitNodeProvider) async -> ExitNode? {
        do {
            let (data, response) = try await session.data(from: provider.endpoint)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            return parse(data: data, provider: provider)
        } catch {
            // 超时/断网/解析失败一律静默降级，不弹错、不重试风暴。
            return nil
        }
    }

    // MARK: - 解析（每个 provider 一个映射，字段缺失留 nil）

    private func parse(data: Data, provider: ExitNodeProvider) -> ExitNode? {
        switch provider {
        case .ipsb:   return parseIPSB(data)
        case .ipapi:  return parseIPAPI(data)
        case .ipinfo: return parseIPInfo(data)
        }
    }

    private func parseIPSB(_ data: Data) -> ExitNode? {
        struct Response: Decodable {
            let ip: String?
            let country: String?
            let country_code: String?
            let city: String?
            let asn: Int?
            let asn_organization: String?
            let organization: String?
            let isp: String?
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data),
              let ip = r.ip, !ip.isEmpty else { return nil }
        return ExitNode(
            ip: ip,
            country: r.country_code,
            countryName: r.country,
            city: r.city,
            asn: r.asn.map { "AS\($0)" },
            org: r.asn_organization ?? r.organization ?? r.isp,
            isHosting: nil,
            fetchedAt: Date()
        )
    }

    private func parseIPAPI(_ data: Data) -> ExitNode? {
        struct Response: Decodable {
            let status: String?
            let query: String?
            let country: String?
            let countryCode: String?
            let city: String?
            let isp: String?
            let org: String?
            let `as`: String?
            let hosting: Bool?
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data),
              r.status == "success",
              let ip = r.query, !ip.isEmpty else { return nil }
        return ExitNode(
            ip: ip,
            country: r.countryCode,
            countryName: r.country,
            city: r.city,
            asn: firstASNToken(r.as),
            org: (r.org?.isEmpty == false ? r.org : nil) ?? r.isp,
            isHosting: r.hosting,
            fetchedAt: Date()
        )
    }

    private func parseIPInfo(_ data: Data) -> ExitNode? {
        struct Response: Decodable {
            let ip: String?
            let city: String?
            let region: String?
            let country: String?
            let org: String?
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data),
              let ip = r.ip, !ip.isEmpty else { return nil }
        // ipinfo 的 org 形如 "AS24940 Hetzner Online GmbH"，拆出 ASN 与组织名。
        let asn = firstASNToken(r.org)
        let org = strippedOrg(r.org, removing: asn)
        return ExitNode(
            ip: ip,
            country: r.country,
            countryName: nil,
            city: r.city,
            asn: asn,
            org: org,
            isHosting: nil,
            fetchedAt: Date()
        )
    }

    // MARK: - 小工具

    /// 取字符串首个形如 "AS24940" 的 token。
    private func firstASNToken(_ raw: String?) -> String? {
        guard let token = raw?.split(separator: " ").first.map(String.init),
              token.hasPrefix("AS"),
              token.dropFirst().allSatisfy(\.isNumber),
              token.count > 2 else { return nil }
        return token
    }

    /// 从 org 字符串里去掉开头的 ASN token，返回纯组织名。
    private func strippedOrg(_ raw: String?, removing asn: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let asn, raw.hasPrefix(asn) else { return raw }
        let rest = raw.dropFirst(asn.count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}
