//
//  AIUsageWindowPicker.swift
//  Light Stats
//
//  Chooses which quota window sits on the compact header, and which
//  windows list under the title after expand.
//

import Foundation

enum AIUsageWindowPicker {
    /// The window that resets soonest. `nil` reset time is never nearest, so an
    /// unknown window cannot hide a dated one. Provider order breaks ties.
    ///
    /// The header answers "which allowance is about to change?", so the nearest
    /// reset wins even when another window is far more consumed: a full 5h
    /// window still resets within hours, while an 88% weekly one is unchanged
    /// tomorrow.
    static func nearestReset(in windows: [UsageWindow]) -> UsageWindow? {
        guard let first = windows.first else { return nil }
        return windows.dropFirst().reduce(first) { current, next in
            isNearer(next, than: current) ? next : current
        }
    }

    /// Period rows under the title. Collapsed and single-window keep the
    /// primary meter on the header, so this is empty until expand.
    static func detailWindows(in windows: [UsageWindow], expanded: Bool) -> [UsageWindow] {
        guard windows.count > 1, expanded else { return [] }
        return windows
    }

    private static func isNearer(_ lhs: UsageWindow, than rhs: UsageWindow) -> Bool {
        switch (lhs.resetsAt, rhs.resetsAt) {
        case let (.some(lhsReset), .some(rhsReset)):
            return lhsReset < rhsReset
        case (.some, .none):
            return true
        case (.none, _):
            return false
        }
    }
}
