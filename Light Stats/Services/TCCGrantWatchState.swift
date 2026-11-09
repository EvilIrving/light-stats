//
//  TCCGrantWatchState.swift
//  Light Stats
//

import Foundation

/// The whole "has the user finished in System Settings?" heuristic, as a value.
///
/// Two facts, and both need hysteresis:
///
/// - **The window count.** A single poll below the peak is not a dismissal — opening a deep link
///   can replace the Settings window, a sidebar click swaps the pane, and either makes the count dip
///   for one tick. Reading that as "the user finished" concluded the flow before the user had done
///   anything, so a drop only counts once it has held for `dismissalSamples` polls.
/// - **The app becoming active again.** This app is in the background while the guide is up, so
///   "is active" alone would fire on the first tick. Only an `false → true` transition counts.
///
/// Pure, and separate from the clock that feeds it, because the failure that matters — concluding
/// the flow on unrelated window churn — is invisible in the live loop.
nonisolated struct TCCGrantWatchState: Sendable, Equatable {

    /// How many consecutive polls with fewer windows than the peak before the drop is believed.
    /// Matches the tracker's own disappearance rule, so the two readings of "gone" agree.
    static let dismissalSamples = SystemSettingsWindowTracker.disappearanceMisses

    private(set) var peak: Int
    private(set) var lowerSamples: Int = 0
    private var sawInactive: Bool

    init(windowCount: Int, isAppActive: Bool) {
        peak = windowCount
        sawInactive = !isAppActive
    }

    /// One poll. Returns the signal it concluded on, or `nil` to keep waiting.
    mutating func observe(windowCount: Int, isAppActive: Bool) -> TCCGrantSignal? {
        if windowCount > peak { peak = windowCount }
        if windowCount < peak {
            lowerSamples += 1
            if lowerSamples >= Self.dismissalSamples { return .settingsDismissed }
        } else {
            lowerSamples = 0
        }

        if isAppActive {
            if sawInactive { return .appReactivated }
        } else {
            sawInactive = true
        }
        return nil
    }
}
