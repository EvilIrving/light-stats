//
//  NetworkInfo.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation

final class NetworkInfo: @unchecked Sendable {

    private var previousBytes: (sent: UInt64, received: UInt64) = (0, 0)
    private var previousTime: Date = Date()

    struct Stats {
        let uploadSpeed: Double
        let downloadSpeed: Double
    }

    func getNetworkStats() -> Stats {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return Stats(uploadSpeed: 0, downloadSpeed: 0)
        }

        defer { freeifaddrs(ifaddr) }

        var totalSent: UInt64 = 0
        var totalReceived: UInt64 = 0

        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback {
                if let ifaAddr = ptr.pointee.ifa_addr,
                   ifaAddr.pointee.sa_family == UInt8(AF_LINK) {
                    if let data = ptr.pointee.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                        totalSent += UInt64(networkData.ifi_obytes)
                        totalReceived += UInt64(networkData.ifi_ibytes)
                    }
                }
            }


            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(previousTime)

        var uploadSpeed: Double = 0
        var downloadSpeed: Double = 0

        if elapsed > 0 && previousBytes.sent > 0 {
            if totalSent >= previousBytes.sent && totalReceived >= previousBytes.received {
                uploadSpeed = Double(totalSent - previousBytes.sent) / elapsed
                downloadSpeed = Double(totalReceived - previousBytes.received) / elapsed
            }
        }

        previousBytes = (totalSent, totalReceived)
        previousTime = now

        return Stats(uploadSpeed: max(0, uploadSpeed), downloadSpeed: max(0, downloadSpeed))
    }

    /// 当前主网卡的接口名与 IPv4 地址（en0 优先）。
    /// 跳过 loopback、127.* 及一众 noise 接口（utun/awdl/bridge 等）。
    /// 标 `nonisolated`：纯 syscall（仅用局部变量），从采集 actor 同步调用，避免占用主线程。
    nonisolated func primaryInterface() -> (name: String, ip: String)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        // 不视为主接口的噪音前缀（隧道、AirDrop、桥接、雷雳等）。
        let noisePrefixes = ["lo", "awdl", "llw", "utun", "tun",
                             "bridge", "gif", "stf", "xhc", "anpi", "ap"]
        var candidates: [(name: String, ip: String)] = []

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }

            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: cur.pointee.ifa_name)
            if noisePrefixes.contains(where: { name.hasPrefix($0) }) { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                     &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }

            let ip = String(cString: host)
            guard !ip.isEmpty, !ip.hasPrefix("127.") else { continue }
            candidates.append((name, ip))
        }

        // 优先 en0，其次任意 en*，再次任意候选。
        if let en0 = candidates.first(where: { $0.name == "en0" }) { return en0 }
        if let en = candidates.first(where: { $0.name.hasPrefix("en") }) { return en }
        return candidates.first
    }
}
