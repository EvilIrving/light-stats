//
//  ProxyDetector.swift
//  Light Stats
//
//  本地代理探测：环境变量 / 系统代理 / 活跃隧道。零外发，纯本地原生 API。
//

import Foundation
import CFNetwork

/// 本地代理探测：按优先级（环境变量 → 系统代理 → 活跃隧道）返回首个命中的配置。
protocol ProxyDetecting {
    nonisolated func currentProxyConfig() -> ProxyConfig
}

/// 整个类型标 `nonisolated`：无状态、纯本地 syscall 服务，不应绑定主线程，
/// 可在采集 actor 上直接同步调用，避免每个刷新周期占用主线程。
nonisolated final class ProxyDetector: ProxyDetecting, Sendable {

    static let shared = ProxyDetector()

    private init() {}

    /// 按优先级探测当前代理配置，三级都没命中则返回 `.none`。
    func currentProxyConfig() -> ProxyConfig {
        if let env = environmentProxyConfig() {
            return env
        }
        if let system = systemProxyConfig() {
            return system
        }
        if let tun = activeTunnelConfig() {
            return tun
        }
        return .none
    }

    // MARK: - ① 环境变量

    /// 读取常见的代理环境变量。以 `socks` 开头判为 `.socks`，否则 `.http`。
    private func environmentProxyConfig() -> ProxyConfig? {
        let env = ProcessInfo.processInfo.environment
        // 优先级：HTTPS > HTTP > ALL（大小写都查）。
        let keys = ["https_proxy", "HTTPS_PROXY",
                    "http_proxy", "HTTP_PROXY",
                    "all_proxy", "ALL_PROXY"]

        for key in keys {
            guard let raw = env[key], !raw.isEmpty,
                  let parsed = parseProxyURLString(raw) else { continue }
            return ProxyConfig(kind: parsed.kind, host: parsed.host, source: "env")
        }
        return nil
    }

    /// 把代理 URL 字符串解析为 (kind, host:port)。支持 `scheme://user:pass@host:port/...`。
    private func parseProxyURLString(_ raw: String) -> (kind: ProxyConfig.Kind, host: String)? {
        var remainder = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return nil }

        var kind: ProxyConfig.Kind = .http
        if let schemeRange = remainder.range(of: "://") {
            let scheme = remainder[..<schemeRange.lowerBound].lowercased()
            kind = scheme.hasPrefix("socks") ? .socks : .http
            remainder = String(remainder[schemeRange.upperBound...])
        }

        // 去掉路径部分。
        if let slash = remainder.firstIndex(of: "/") {
            remainder = String(remainder[..<slash])
        }
        // 去掉 user:pass@ 凭证部分。
        if let at = remainder.lastIndex(of: "@") {
            remainder = String(remainder[remainder.index(after: at)...])
        }

        let host = remainder.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }
        return (kind, host)
    }

    // MARK: - ② 系统代理（CFNetworkCopySystemProxySettings，替代 scutil --proxy）

    private func systemProxyConfig() -> ProxyConfig? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        func isEnabled(_ key: CFString) -> Bool {
            (settings[key as String] as? NSNumber)?.intValue == 1
        }
        func string(_ key: CFString) -> String? {
            settings[key as String] as? String
        }
        func port(_ key: CFString) -> Int? {
            (settings[key as String] as? NSNumber)?.intValue
        }

        // 优先级：HTTPS > HTTP > SOCKS > PAC。
        if isEnabled(kCFNetworkProxiesHTTPSEnable), let host = string(kCFNetworkProxiesHTTPSProxy) {
            return ProxyConfig(kind: .https,
                               host: hostPort(host, port(kCFNetworkProxiesHTTPSPort)),
                               source: "system")
        }
        if isEnabled(kCFNetworkProxiesHTTPEnable), let host = string(kCFNetworkProxiesHTTPProxy) {
            return ProxyConfig(kind: .http,
                               host: hostPort(host, port(kCFNetworkProxiesHTTPPort)),
                               source: "system")
        }
        if isEnabled(kCFNetworkProxiesSOCKSEnable), let host = string(kCFNetworkProxiesSOCKSProxy) {
            return ProxyConfig(kind: .socks,
                               host: hostPort(host, port(kCFNetworkProxiesSOCKSPort)),
                               source: "system")
        }
        if isEnabled(kCFNetworkProxiesProxyAutoConfigEnable),
           let url = string(kCFNetworkProxiesProxyAutoConfigURLString) {
            return ProxyConfig(kind: .pac, host: url, source: "system")
        }
        return nil
    }

    private func hostPort(_ host: String, _ port: Int?) -> String {
        if let port, port > 0 {
            return "\(host):\(port)"
        }
        return host
    }

    // MARK: - ③ 活跃隧道（utun/tun 且有流量）

    /// 遍历接口找出 `utun*`/`tun*` 且收发字节 > 0 的隧道。注意：VPN / iCloud
    /// Private Relay / Clash TUN 都会建 utun，可能误报，故 UI 上用「检测到隧道」弱措辞。
    private func activeTunnelConfig() -> ProxyConfig? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }

            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0 else { continue }
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let name = String(cString: cur.pointee.ifa_name)
            guard name.hasPrefix("utun") || name.hasPrefix("tun") else { continue }

            if let data = cur.pointee.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                if UInt64(networkData.ifi_obytes) + UInt64(networkData.ifi_ibytes) > 0 {
                    return ProxyConfig(kind: .tun, host: name, source: "tun")
                }
            }
        }
        return nil
    }
}
