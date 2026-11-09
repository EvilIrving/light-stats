//
//  TCCGrantWatcher.swift
//  Light Stats
//

import AppKit

/// Waits for the guide's conclusion, then says what happened.
///
/// The decisions themselves are values — `TCCGrantWatchState.observe` for the heuristic and
/// `TCCGrantResult.resolve` for the table over `(signal, final read)`, both tested. This class is
/// only the clock and the two live probes.
///
/// The 200 ms settle after a dismissal-style signal is the load-bearing number: TCC writes the grant
/// *after* the sheet starts animating out, so an immediate read reports a refusal for a grant the
/// user just made. One sleep, one read — not a retry loop, because for Screen Recording no number
/// of retries can ever converge.
@MainActor
final class TCCGrantWatcher {

    nonisolated static let pollInterval: TimeInterval = 0.12
    /// The budget is "read the sentence, find the icon, drag it into the list, answer the TCC
    /// sheet". Ten seconds was shorter than the gesture it was waiting for: the card was ordered
    /// out mid-drag and the session died with it.
    nonisolated static let timeout: TimeInterval = 45
    nonisolated static let settleDelay: TimeInterval = 0.2

    private let readGrant: () -> Bool
    private let settingsWindowCount: () async -> Int

    init(
        readGrant: @escaping () -> Bool,
        settingsWindowCount: @escaping () async -> Int = { await SystemSettingsWindowTracker.scanWindowCount() }
    ) {
        self.readGrant = readGrant
        self.settingsWindowCount = settingsWindowCount
    }

    func wait(timeout: TimeInterval = TCCGrantWatcher.timeout) async -> TCCGrantResult {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var state = TCCGrantWatchState(windowCount: await settingsWindowCount(), isAppActive: NSApp.isActive)

        while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
            if readGrant() { return .granted }

            let count = await settingsWindowCount()
            guard !Task.isCancelled else { return .timedOut }
            if let signal = state.observe(windowCount: count, isAppActive: NSApp.isActive) {
                return await settle(signal)
            }

            try? await Task.sleep(for: .milliseconds(Int(Self.pollInterval * 1000)))
        }

        guard !Task.isCancelled else { return .timedOut }
        return TCCGrantResult.resolve(.timedOut, isGranted: readGrant())
    }

    private func settle(_ signal: TCCGrantSignal) async -> TCCGrantResult {
        try? await Task.sleep(for: .milliseconds(Int(Self.settleDelay * 1000)))
        return TCCGrantResult.resolve(signal, isGranted: readGrant())
    }
}
