//
//  DDCBusState.swift
//  Light Stats
//

import Foundation

nonisolated final class DDCBusState: @unchecked Sendable {
    private let lock = NSLock()
    private var hung = false
    private var activeCallID: UUID?

    var isHung: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hung
    }

    var hasActiveCall: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeCallID != nil
    }

    func beginCall() -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard !hung, activeCallID == nil else { return nil }
        let callID = UUID()
        activeCallID = callID
        return callID
    }

    func completeCall(_ callID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if activeCallID == callID {
            activeCallID = nil
        }
    }

    func markHung() {
        lock.lock()
        defer { lock.unlock() }
        hung = true
    }

    func resetHung() {
        lock.lock()
        defer { lock.unlock() }
        hung = false
    }
}
