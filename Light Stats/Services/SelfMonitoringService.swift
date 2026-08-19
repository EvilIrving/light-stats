//
//  SelfMonitoringService.swift
//  Light Stats
//

import Darwin
import Foundation

/// Samples this process only. CPU is a delta between one-minute recording samples;
/// cumulative counters are kept alongside it so later analysis can derive other rates.
actor SelfMonitoringService {
    private var previousSessionID: String?
    private var previousCPUTimeNanoseconds: UInt64?
    private var previousUptime: TimeInterval?

    func sample(sessionID: String) -> SelfMonitoringSample? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            proc_pid_rusage(
                getpid(),
                RUSAGE_INFO_V4,
                UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self)
            )
        }
        guard result == 0 else { return nil }

        let uptime = ProcessInfo.processInfo.systemUptime
        let totalCPUTime = usage.ri_user_time + usage.ri_system_time
        let cpuPercent = cpuPercent(
            sessionID: sessionID,
            totalCPUTimeNanoseconds: totalCPUTime,
            uptime: uptime
        )

        return SelfMonitoringSample(
            cpuPercent: cpuPercent,
            cpuUserSeconds: Double(usage.ri_user_time) / 1_000_000_000,
            cpuSystemSeconds: Double(usage.ri_system_time) / 1_000_000_000,
            physicalFootprintBytes: usage.ri_phys_footprint,
            peakPhysicalFootprintBytes: usage.ri_lifetime_max_phys_footprint,
            residentBytes: usage.ri_resident_size,
            wiredBytes: usage.ri_wired_size,
            threadCount: threadCount(),
            idleWakeups: usage.ri_pkg_idle_wkups,
            interruptWakeups: usage.ri_interrupt_wkups,
            pageIns: usage.ri_pageins,
            diskBytesRead: usage.ri_diskio_bytesread,
            diskBytesWritten: usage.ri_diskio_byteswritten
        )
    }

    private func cpuPercent(
        sessionID: String,
        totalCPUTimeNanoseconds: UInt64,
        uptime: TimeInterval
    ) -> Double? {
        defer {
            previousSessionID = sessionID
            previousCPUTimeNanoseconds = totalCPUTimeNanoseconds
            previousUptime = uptime
        }
        guard previousSessionID == sessionID,
              let previousCPUTimeNanoseconds,
              let previousUptime,
              totalCPUTimeNanoseconds >= previousCPUTimeNanoseconds else { return nil }

        let elapsed = uptime - previousUptime
        guard elapsed > 0 else { return nil }
        let cpuSeconds = Double(totalCPUTimeNanoseconds - previousCPUTimeNanoseconds) / 1_000_000_000
        return max(0, cpuSeconds / elapsed * 100)
    }

    private func threadCount() -> Int? {
        var info = proc_taskinfo()
        let expectedSize = MemoryLayout<proc_taskinfo>.size
        let actualSize = proc_pidinfo(
            getpid(),
            PROC_PIDTASKINFO,
            0,
            &info,
            Int32(expectedSize)
        )
        guard actualSize == expectedSize else { return nil }
        return Int(info.pti_threadnum)
    }
}
