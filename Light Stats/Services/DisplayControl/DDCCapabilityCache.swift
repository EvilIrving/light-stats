//
//  DDCCapabilityCache.swift
//  Light Stats
//

import Foundation

nonisolated final class DDCCapabilityCache: @unchecked Sendable {
    struct Entry: Sendable {
        let capability: DisplayControlCapability
        let code: DDCVCPCode?
        let maximum: UInt16?
    }

    private let lock = NSLock()
    private var entries: [UInt32: Entry] = [:]

    func entry(for displayID: UInt32) -> Entry {
        lock.lock()
        defer { lock.unlock() }
        return entries[displayID] ?? Entry(capability: .unknown, code: nil, maximum: nil)
    }

    func setSupported(displayID: UInt32, code: DDCVCPCode, maximum: UInt16) {
        set(
            Entry(capability: .supported, code: code, maximum: DDCRawConversion.sanitizedMaximum(maximum)),
            for: displayID
        )
    }

    func setUnsupported(displayID: UInt32) {
        set(Entry(capability: .unsupported, code: nil, maximum: nil), for: displayID)
    }

    func setUnknown(displayID: UInt32) {
        set(Entry(capability: .unknown, code: nil, maximum: nil), for: displayID)
    }

    func setPreferredCode(displayID: UInt32, code: DDCVCPCode, maximum: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        let current = entries[displayID]
        entries[displayID] = Entry(
            capability: current?.capability ?? .unknown,
            code: code,
            maximum: DDCRawConversion.sanitizedMaximum(current?.maximum ?? maximum)
        )
    }

    func reset(displayID: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: displayID)
    }

    func retain(displayIDs: Set<UInt32>) {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { displayIDs.contains($0.key) }
    }

    private func set(_ entry: Entry, for displayID: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        entries[displayID] = entry
    }
}
