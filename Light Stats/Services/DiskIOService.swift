//
//  DiskIOService.swift
//  Light Stats
//
//  磁盘 IO 读/写速率：遍历 IOBlockStorageDriver 的 Statistics 字典取累计读写字节，
//  差值法算速率（参考 NetworkInfo 的 previousBytes 模式）。原生 IOKit，零外发。
//

import Foundation
import IOKit

/// 磁盘 IO 采集器（有状态：保存上次字节数与时间戳）。
/// 标 `nonisolated`：纯 syscall，在采集 actor 上同步执行，避免占用主线程。
/// `@unchecked Sendable`：仅被 `MonitorSampler` 串行调用，状态访问天然无竞争。
nonisolated final class DiskIOService: @unchecked Sendable {

    private var previousRead: UInt64 = 0
    private var previousWrite: UInt64 = 0
    private var previousTime: Date = Date()
    private var hasPrevious = false

    /// 采样一次读/写速率。首样本返回 0（无基准）。计数器回绕/重置（负差值）夹到 0。
    func sample() -> DiskIOStats {
        let (read, write) = Self.totalBytes()
        let now = Date()
        let elapsed = now.timeIntervalSince(previousTime)

        var readMBs: Double = 0
        var writeMBs: Double = 0
        if hasPrevious, elapsed > 0 {
            if read >= previousRead {
                readMBs = Double(read - previousRead) / elapsed / 1_000_000
            }
            if write >= previousWrite {
                writeMBs = Double(write - previousWrite) / elapsed / 1_000_000
            }
        }

        previousRead = read
        previousWrite = write
        previousTime = now
        hasPrevious = true

        return DiskIOStats(readMBs: Swift.max(0, readMBs), writeMBs: Swift.max(0, writeMBs))
    }

    /// 聚合所有块设备驱动的累计读/写字节。
    private static func totalBytes() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == kIOReturnSuccess else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = propsRef?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                if let r = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value {
                    totalRead += r
                }
                if let w = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value {
                    totalWrite += w
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return (totalRead, totalWrite)
    }
}
