//
//  UsageWindow.swift
//  Light Stats
//

import Foundation

/// A single rate-limit window (e.g. 5h or weekly).
struct UsageWindow: Codable, Equatable, Sendable {
    /// A `UsageWindowLabel` key, or a provider-supplied literal (`5h`, `Pro`, …).
    let label: String
    /// `nil` when the provider reports a window but not a used percent.
    let usedPercent: Double?
    let resetsAt: Date?

    init(label: String, usedPercent: Double?, resetsAt: Date?) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    init(label: UsageWindowLabel, usedPercent: Double?, resetsAt: Date?) {
        self.init(label: label.key, usedPercent: usedPercent, resetsAt: resetsAt)
    }
}
