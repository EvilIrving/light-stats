//
//  ApplicationActivationTracker.swift
//  Light Stats
//

import AppKit
import Foundation

/// Records which applications the user has used, most recent first.
///
/// The switcher needs this order and `NSWorkspace` does not publish it: `runningApplications` is
/// ordered by launch, not by use, so ordering by it would produce a switcher whose first Tab goes
/// somewhere the user has not touched in hours.
///
/// Lock-protected rather than actor-isolated because the ⌘Tab event tap reads it from its own
/// thread, inside the event callback, where hopping to the main actor is not an option.
nonisolated final class ApplicationActivationTracker: @unchecked Sendable {

    static let shared = ApplicationActivationTracker()

    private let lock = NSLock()
    private var recency: [pid_t] = []
    private let maximumEntries = 40

    /// PIDs, most recently activated first.
    var order: [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        return recency
    }

    private init() {}

    func record(processID: pid_t) {
        guard processID != ProcessInfo.processInfo.processIdentifier else { return }
        lock.lock()
        recency.removeAll { $0 == processID }
        recency.insert(processID, at: 0)
        if recency.count > maximumEntries {
            recency.removeLast(recency.count - maximumEntries)
        }
        lock.unlock()
    }

    /// Seeds the order at launch from the applications already running, so the very first ⌘Tab of a
    /// session is not arbitrary.
    func seed(from applications: [NSRunningApplication]) {
        lock.lock()
        defer { lock.unlock() }
        guard recency.isEmpty else { return }
        recency = applications
            .filter {
                $0.activationPolicy == .regular
                    && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }
            .map(\.processIdentifier)
    }

    /// Drops entries for applications that have quit, so a long session does not accumulate PIDs
    /// that no longer mean anything.
    func prune(keeping running: Set<pid_t>) {
        lock.lock()
        recency.removeAll { !running.contains($0) }
        lock.unlock()
    }

    /// Test seam.
    func reset() {
        lock.lock()
        recency.removeAll()
        lock.unlock()
    }
}
