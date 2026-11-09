//
//  TCCGrantSignal.swift
//  Light Stats
//

import Foundation

/// What one of the three things the watcher can notice means.
///
/// There is deliberately no "the permission API flipped while we watched" case: a readable grant is
/// read on the first poll of every tick, so it is the watcher's answer rather than a signal it
/// concludes from — the signals below exist only to say *what a `false` read means*.
nonisolated enum TCCGrantSignal: Sendable, Equatable {
    /// The System Settings window count stayed below the peak it reached — a privacy sheet
    /// finished, whichever answer it carried.
    case settingsDismissed
    /// The app became active again after having been in the background.
    case appReactivated
    /// Nothing at all happened inside the budget.
    case timedOut
}
