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
    /// primary cabin on the header, so this is empty until expand.
    /// Expanded order is the hero cabin first, then the others in provider order.
    static func detailWindows(in windows: [UsageWindow], expanded: Bool) -> [UsageWindow] {
        guard windows.count > 1, expanded, let hero = mostStrained(in: windows) else {
            return []
        }
        return [hero] + supportingWindows(in: windows)
    }

    /// Every window except the most-strained hero, in the provider's order.
    static func supportingWindows(in windows: [UsageWindow]) -> [UsageWindow] {
        guard let hero = mostStrained(in: windows) else { return [] }
        return windows.filter { $0.label != hero.label }
    }

    private static func strain(_ window: UsageWindow) -> Double {
        window.usedPercent ?? -1
    }
}
