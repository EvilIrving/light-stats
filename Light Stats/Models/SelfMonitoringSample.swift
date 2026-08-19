//
//  SelfMonitoringSample.swift
//  Light Stats
//

/// Lightweight resource snapshot for the Light Stats process itself.
nonisolated struct SelfMonitoringSample: Sendable {
    let cpuPercent: Double?
    let cpuUserSeconds: Double
    let cpuSystemSeconds: Double
    let physicalFootprintBytes: UInt64
    let peakPhysicalFootprintBytes: UInt64
    let residentBytes: UInt64
    let wiredBytes: UInt64
    let threadCount: Int?
    let idleWakeups: UInt64
    let interruptWakeups: UInt64
    let pageIns: UInt64
    let diskBytesRead: UInt64
    let diskBytesWritten: UInt64
}
