//
//  WindowPreviewIndex.swift
//  Light Stats
//

import AppKit
import OSLog

/// A cached snapshot of every application's windows.
///
/// The ⌘Tab tap has to answer "what can I switch to?" **inside the event callback**. Doing
/// Accessibility enumeration there would block the event tap on every keypress — and a slow tap is
/// one macOS disables. So the enumeration happens here, on the shared AX queue and off this
/// thread, and the tap only ever reads an immutable array under a lock.
///
/// Staleness is handled by refreshing rather than by refusing to answer: a snapshot a few seconds
/// old still contains the right applications and almost always the right windows, and the very
/// first ⌘Tab of a session is far better served by a slightly stale list than by a blocked tap.
/// Three caches with their own lifetimes keep the tap's answers cheap. The alternative —
/// enumerating inside the event callback — is what makes a tap slow enough for macOS to disable.
nonisolated final class WindowPreviewIndex: @unchecked Sendable {

    static let shared = WindowPreviewIndex()
    var onRefresh: (([ApplicationWindowGroup]) -> Void)?

    private let logger = AppLogger(category: "WindowPreviewIndex")
    private let lock = NSLock()

    private var groups: [ApplicationWindowGroup] = []
    private var refreshedAt: TimeInterval = -.infinity
    private var isRefreshing = false
    private var configuration: SnapConfiguration = .default
    private var enabled = false
    private var generation: UInt64 = 0

    /// How long a snapshot is considered good enough to answer from without a refresh in flight.
    private let freshness: TimeInterval = 4

    private init() {}

    // MARK: - Reading

    /// Every application group, newest snapshot. Never blocks and never touches Accessibility.
    func currentGroups() -> [ApplicationWindowGroup] {
        lock.lock()
        let snapshot = groups
        let stale = ProcessInfo.processInfo.systemUptime - refreshedAt > freshness
        lock.unlock()
        if stale {
            refresh()
        }
        return snapshot
    }

    func group(for processID: pid_t) -> ApplicationWindowGroup? {
        lock.lock()
        let match = groups.first { $0.processID == processID }
        lock.unlock()
        return match
    }

    func allGroups() -> [ApplicationWindowGroup] {
        lock.lock()
        defer { lock.unlock() }
        return groups
    }

    // MARK: - Configuration

    func update(configuration: SnapConfiguration, enabled: Bool = true) {
        lock.lock()
        self.configuration = configuration
        self.enabled = enabled
        generation &+= 1
        if !enabled { groups = [] }
        refreshedAt = -.infinity
        lock.unlock()
        refresh()
    }

    func loadGroup(for processID: pid_t) async -> ApplicationWindowGroup? {
        let exclusions = currentExclusions()
        guard let exclusions else { return nil }
        return await Task.detached(priority: .userInitiated) {
            WindowPreviewCatalog.groups(exclusions: exclusions, processID: processID).first
        }.value
    }

    private func currentExclusions() -> Set<String>? {
        lock.lock(); defer { lock.unlock() }
        return enabled ? configuration.exclusionSet : nil
    }

    /// Forces a refresh — used when an application launches, quits, or comes forward, which are the
    /// moments the answer genuinely changes.
    func invalidate() {
        lock.lock()
        refreshedAt = -.infinity
        lock.unlock()
        refresh()
    }

    // MARK: - Refreshing

    private func refresh() {
        lock.lock()
        guard enabled, !isRefreshing else {
            lock.unlock()
            return
        }
        isRefreshing = true
        let configuration = self.configuration
        let token = generation
        lock.unlock()

        Task.detached(priority: .userInitiated) { [weak self] in
            self?.refreshSnapshot(configuration: configuration, token: token)
        }
    }

    private func refreshSnapshot(configuration: SnapConfiguration, token: UInt64) {
            let started = ProcessInfo.processInfo.systemUptime
            let enumerated = WindowPreviewCatalog.groups(exclusions: configuration.exclusionSet)
            DiagnosticLogService.record(category: "windowManagement", action: "previewInventory", fields: [
                "source": "accessibility", "applications": String(enumerated.count),
                "windows": String(enumerated.reduce(0) { $0 + $1.windows.count }),
                "durationMS": String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - started) * 1000)
            ])

            self.lock.lock()
            let isCurrent = self.enabled && self.generation == token
            if isCurrent {
                self.groups = enumerated
                self.refreshedAt = ProcessInfo.processInfo.systemUptime
            }
            self.isRefreshing = false
            let retry = self.enabled && !isCurrent
            self.lock.unlock()
            if isCurrent {
                Task { @MainActor [weak self] in self?.onRefresh?(enumerated) }
            }
            if retry { self.refresh() }
    }
}
