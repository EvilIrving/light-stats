//
//  AIUsageWindowPicker.swift
//  Light Stats
//
//  Chooses which quota window sits on the compact header, and which
//  windows list under the title after expand.
//

import Foundation

enum AIUsageWindowPicker {
    /// Highest `usedPercent` (lowest remaining). `nil` percent is least strained
    /// so an unlimited / unknown window never hides a real quota.
    static func mostStrained(in windows: [UsageWindow]) -> UsageWindow? {
        guard let first = windows.first else { return nil }
        return windows.dropFirst().reduce(first) { current, next in
            strain(next) > strain(current) ? next : current
        }
    }

    /// Period rows under the title. Collapsed and single-window keep the
    /// primary meter on the header, so this is empty until expand.
    static func detailWindows(in windows: [UsageWindow], expanded: Bool) -> [UsageWindow] {
        guard windows.count > 1, expanded else { return [] }
        return windows
    }

    private static func strain(_ window: UsageWindow) -> Double {
        window.usedPercent ?? -1
    }
}
