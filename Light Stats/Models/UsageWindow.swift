//
//  UsageWindow.swift
//  Light Stats
//

import Foundation

/// A single rate-limit window (e.g. 5h or weekly).
struct UsageWindow: Codable, Hashable, Sendable {
    /// A `UsageWindowLabel` key, or a provider-supplied literal (`5h`, `Pro`, …).
    let label: String
    /// The allowance this window belongs to, as a localization key. `nil` for
    /// the providers that meter one allowance only.
    ///
    /// Antigravity is the case this exists for: Gemini and the third-party
    /// models are separate pools with their own 5h and weekly windows, so the
    /// window kind alone cannot identify a row.
    let pool: String?
    /// `nil` when the provider reports a window but not a used percent.
    let usedPercent: Double?
    let resetsAt: Date?

    init(label: String, pool: String? = nil, usedPercent: Double?, resetsAt: Date?) {
        self.label = label
        self.pool = pool
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    init(label: UsageWindowLabel, usedPercent: Double?, resetsAt: Date?) {
        self.init(label: label.key, usedPercent: usedPercent, resetsAt: resetsAt)
    }
}
