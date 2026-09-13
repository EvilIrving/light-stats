//
//  AIUsageWindowPicker.swift
//  Light Stats
//
//  Chooses which quota windows a compact provider row should show.
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

    /// Collapsed multi-window rows show only the tightest window; expanded and
    /// single-window rows keep the provider's original order.
    static func visibleWindows(in windows: [UsageWindow], expanded: Bool) -> [UsageWindow] {
        guard windows.count > 1, !expanded, let primary = mostStrained(in: windows) else {
            return windows
        }
        return [primary]
    }

    private static func strain(_ window: UsageWindow) -> Double {
        window.usedPercent ?? -1
    }
}
