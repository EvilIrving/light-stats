//
//  WindowVisibilityService.swift
//  Light Stats
//

import AppKit

/// Tracks our own hides by process identity. AppKit's return value is only a request result;
/// on macOS 26 a false return can still change visibility. Observe the state after the run loop
/// advances, and retain failed restores so the next gesture can retry them.
nonisolated final class WindowVisibilityService: @unchecked Sendable {
    struct Application: Sendable {
        let identity: ProcessIdentity
        var isHidden: Bool
        var isRegular = true
    }

    struct Outcome: Sendable {
        let command: WindowVisibilityCommand
        let changed: Int
        let failed: Int
        let reason: String

        var succeeded: Bool { changed > 0 && failed == 0 && reason == "confirmed" }
    }

    struct Client: Sendable {
        var applications: @MainActor @Sendable () -> [Application]
        var request: @MainActor @Sendable (ProcessIdentity, Bool) -> Bool
        var wait: @MainActor @Sendable () async -> Void

        static let live = Client(
            applications: {
                NSWorkspace.shared.runningApplications.compactMap { app in
                    guard let identity = ProcessIdentityReader.read(app.processIdentifier) else { return nil }
                    return Application(identity: identity, isHidden: app.isHidden, isRegular: app.activationPolicy == .regular)
                }
            },
            request: { identity, hidden in
                guard ProcessIdentityReader.read(identity.pid) == identity,
                      let app = NSRunningApplication(processIdentifier: identity.pid) else { return false }
                return hidden ? app.hide() : app.unhide()
            },
            wait: { try? await Task.sleep(for: .milliseconds(50)) }
        )
    }

    static var historyURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Light Stats/WindowVisibility/hidden-applications.json")
    }

    private let client: Client
    private let storageURL: URL?
    private let ownPID: Int32
    private let stateLock = NSLock()
    private var hiddenApplications: Set<ProcessIdentity>
    private var revision: UInt64 = 0
    @MainActor private var operationInFlight = false

    init(client: Client = .live, storageURL: URL? = WindowVisibilityService.historyURL,
         ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.client = client
        self.storageURL = storageURL
        self.ownPID = ownPID
        if let storageURL, let data = try? Data(contentsOf: storageURL),
           let saved = try? JSONDecoder().decode(Set<ProcessIdentity>.self, from: data) {
            hiddenApplications = saved
        } else {
            hiddenApplications = []
        }
    }

    var hiddenCount: Int { state().applications.count }

    /// A nil command is the shake toggle. Resolve it from fresh visibility, inside the same
    /// serialized operation that submits and confirms the requests.
    @MainActor
    func perform(_ requestedCommand: WindowVisibilityCommand?, keeping processID: Int32?) async -> Outcome? {
        guard !operationInFlight else {
            DiagnosticLogService.record(category: "windowManagement", action: "visibilityBusy")
            return nil
        }
        operationInFlight = true
        defer { operationInFlight = false }

        let initial = client.applications()
        let saved = state()
        let currentlyHidden = Set(initial.filter(\.isHidden).map(\.identity))
        let tracked = saved.applications.intersection(currentlyHidden)
        guard replaceHistory(tracked, revision: saved.revision) else { return nil }
        let command = requestedCommand ?? ShakeVisibilityPolicy.command(hasHiddenApplications: !tracked.isEmpty)
        let hiding = command != .restore
        let eligible = initial.filter { app in
            guard app.identity.pid != ownPID else { return false }
            if !hiding { return tracked.contains(app.identity) }
            return app.isRegular && (command == .hideAll || app.identity.pid != processID)
        }
        let targets = Set(eligible.filter { $0.isHidden != hiding }.map(\.identity))
        let alreadyHidden = hiding ? eligible.filter(\.isHidden).count : 0

        // Save intent before sending requests, so a relaunch mid-operation does not lose undo.
        // On the next operation, records are checked against live visibility and BSD start time.
        if hiding, !replaceHistory(tracked.union(targets), revision: saved.revision) { return nil }
        var requestReturnedFalse = 0
        for identity in targets where !client.request(identity, hiding) {
            requestReturnedFalse += 1
        }

        var observed = initial
        if !targets.isEmpty {
            for _ in 0..<10 {
                await client.wait()
                guard state().revision == saved.revision else {
                    return Outcome(command: command, changed: 0, failed: targets.count, reason: "cancelled")
                }
                observed = client.applications()
                let unsettled = observed.contains { targets.contains($0.identity) && $0.isHidden != hiding }
                if !unsettled { break }
            }
        }

        let hiddenNow = Set(observed.filter(\.isHidden).map(\.identity))
        let visibleNow = Set(observed.filter { !$0.isHidden }.map(\.identity))
        let confirmed = targets.intersection(hiding ? hiddenNow : visibleNow)
        // A failed unhide must stay recoverable. Exited/replaced processes and apps the user
        // already revealed drop out; an identical PID with a new start time is never acted on.
        let remaining = (hiding ? tracked.union(targets) : tracked).intersection(hiddenNow)
        guard replaceHistory(remaining, revision: saved.revision) else { return nil }
        let failed = targets.count - confirmed.count
        let reason = targets.isEmpty ? "noTargets" : (failed == 0 ? "confirmed" : "unconfirmed")
        DiagnosticLogService.record(
            level: failed > 0 ? .warning : .info,
            category: "windowManagement",
            action: hiding ? "visibilityHidden" : "visibilityRestored",
            fields: [
                "source": requestedCommand == nil ? "shake" : "command",
                "reasonCode": reason,
                "attempted": String(targets.count),
                "confirmed": String(confirmed.count),
                "failed": String(failed),
                "requestReturnedFalse": String(requestReturnedFalse),
                "alreadyHidden": String(alreadyHidden),
                "tracked": String(remaining.count)
            ]
        )
        return Outcome(command: command, changed: confirmed.count, failed: failed, reason: reason)
    }

    /// Switching window management off forgets ownership without revealing applications.
    func forgetHistory() {
        stateLock.lock()
        defer { stateLock.unlock() }
        revision &+= 1
        hiddenApplications.removeAll()
        persistHistory()
    }

    private func state() -> (applications: Set<ProcessIdentity>, revision: UInt64) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (hiddenApplications, revision)
    }

    @discardableResult
    private func replaceHistory(_ applications: Set<ProcessIdentity>, revision expectedRevision: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard revision == expectedRevision else { return false }
        guard hiddenApplications != applications else { return true }
        hiddenApplications = applications
        persistHistory()
        return true
    }

    /// Called under stateLock, so an older operation cannot overwrite a later forget.
    private func persistHistory() {
        guard let storageURL else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(hiddenApplications).write(to: storageURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        } catch {
            DiagnosticLogService.record(level: .error, category: "windowManagement", action: "visibilityHistoryWriteFailed",
                                        fields: ["reasonCode": "storageUnavailable"])
        }
    }
}
