//
//  ProxyInfo.swift
//  Light Stats
//
//  Created on 2026/06/06.
//

import Foundation

/// 本地代理配置：系统/环境变量/活跃隧道是否配了代理（零外发探测的结果）。
/// 纯数据模型标 `nonisolated`，computed/static 成员可在非主线程的采集 actor 上访问。
nonisolated struct ProxyConfig: Sendable, Equatable {
    enum Kind: Sendable {
        case none
        case http
        case https
        case socks
        case pac
        case tun
    }

    var kind: Kind
    /// 例如 "127.0.0.1:7890"；PAC 时为 URL；TUN 时为接口名（如 "utun4"）。
    var host: String?
    /// 来源标识："system" | "env" | "tun"。
    var source: String

    var isEnabled: Bool { kind != .none }

    /// 未检测到任何代理配置时的占位值。
    static let none = ProxyConfig(kind: .none, host: nil, source: "")
}

/// 公网出口节点（仅在出口探测开启且成功时才有值）。
nonisolated struct ExitNode: Sendable, Equatable {
    var ip: String
    var country: String?        // "JP"
    var countryName: String?    // "Japan"
    var city: String?
    var asn: String?            // "AS24940"
    var org: String?            // "Hetzner Online GmbH"
    var isHosting: Bool?        // 机房/IDC 判定（provider 提供时）
    var fetchedAt: Date
}

/// 一致性结论：综合本地代理配置与出口节点判断当前是否在走代理。
nonisolated enum NetworkRoute: Sendable {
    case direct
    case proxied    // 检出代理配置 或 出口异常
    case unknown    // 出口探测关闭/失败时
}

/// 综合本地代理配置与出口节点，给出一致性判断。
/// - 出口探测关闭/失败（exit == nil）：有本地代理 → `.proxied`，否则 `.unknown`。
/// - 有出口：出口为机房 IDC 或有本地代理 → `.proxied`，否则 `.direct`。
/// （进阶可比对出口 ASN/国家与本地 ISP，本期暂不做地理比对。）
///
/// 标 `nonisolated`：纯函数，无需主线程隔离，可在采集 actor 上直接同步调用。
nonisolated func classifyRoute(proxy: ProxyConfig, exit: ExitNode?) -> NetworkRoute {
    guard let exit else {
        return proxy.isEnabled ? .proxied : .unknown
    }
    if exit.isHosting == true || proxy.isEnabled {
        return .proxied
    }
    return .direct
}
