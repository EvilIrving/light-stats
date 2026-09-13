//
//  UsageWindowLabel.swift
//  Light Stats
//

import Foundation

/// Language-neutral token for a usage-window label.
///
/// Providers emit a token instead of display text; the panel resolves it at render
/// time, so switching language does not need a refetch to re-label existing rows.
enum UsageWindowLabel: String, Sendable, CaseIterable {
    /// Remaining subscription credits.
    case quota
    /// Consumed share of the included allowance.
    case usage
    /// Consumption past the included allowance.
    case overage
    /// A calendar-month window.
    case month

    var key: String { "aiUsage.window.\(rawValue)" }
}
