//
//  PageRateService.swift
//  Light Stats
//
//  换页速率采集：从 vm_statistics64 取累计 swapins/swapouts（写入/读出磁盘 swap 的页数），
//  差值法算「此刻」的换页速率（MB/s）。这是真实的内存颠簸信号——
//  和 swap **占用量**（缓变、压力消退后仍滞留）不同，速率反映系统当下是否正在颠簸。
//

import Foundation

/// 换页速率采集器（有状态：保存上次累计页数与时间戳）。
/// 标 `nonisolated`：纯 syscall，在采集 actor 上同步执行，避免占用主线程。
/// `@unchecked Sendable`：仅被 `MonitorSampler` 串行调用，状态访问天然无竞争。
nonisolated final class PageRateService: @unchecked Sendable {

    private var previousPages: UInt64 = 0
    private var previousTime: Date = Date()
    private var hasPrevious = false

    /// 采样一次磁盘 swap 换页速率（MB/s）。首样本返回 0（无基准）。
    /// 计数器回绕/重置（负差值）夹到 0。
    func sample() -> Double {
        let pages = Self.totalSwapPages()
        let now = Date()
        let elapsed = now.timeIntervalSince(previousTime)

        var rateMBs: Double = 0
        if hasPrevious, elapsed > 0, pages >= previousPages {
            let pageSize = Double(vm_kernel_page_size)
            rateMBs = Double(pages - previousPages) * pageSize / elapsed / 1_000_000
        }

        previousPages = pages
        previousTime = now
        hasPrevious = true

        return Swift.max(0, rateMBs)
    }

    /// 累计 swapins + swapouts 页数。磁盘 swap 进出量是「颠簸」最直接的信号；
    /// 压缩器拦截了大部分换页，只有压缩池溢出到磁盘时这两个计数才上涨。
    private static func totalSwapPages() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(stats.swapins) + UInt64(stats.swapouts)
    }
}
