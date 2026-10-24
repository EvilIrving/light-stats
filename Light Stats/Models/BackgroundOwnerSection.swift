//
//  BackgroundOwnerSection.swift
//  Light Stats
//

import Foundation

/// One owner's members inside the background row.
///
/// Background processes are grouped by the installed application behind them, so a row that could
/// only say "后台进程" can name the products it holds. Processes with no installed owner stay
/// together under `unownedKey`.
nonisolated struct BackgroundOwnerSection: Identifiable, Sendable {
    static let unownedKey = "unowned"

    let id: String
    let name: String
    let totalMemoryBytes: UInt64
    let pids: [pid_t]
    let unavailableMemoryCount: Int

    var isUnowned: Bool {
        id == Self.unownedKey
    }

    /// Known subtotal with `≥`, or `—` when nothing about this owner is known.
    var memoryFormatted: String {
        guard unavailableMemoryCount < pids.count else { return "—" }
        let prefix = unavailableMemoryCount > 0 ? "≥ " : ""
        return prefix + ByteFormatter.format(totalMemoryBytes)
    }
}
