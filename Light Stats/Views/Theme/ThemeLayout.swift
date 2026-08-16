//
//  ThemeLayout.swift
//  Light Stats
//
//  Overview / Cleanup chrome fork. Resolved by `ThemeDefinition`, not by
//  comparing `AppTheme` cases in business views.
//

import Foundation

enum ThemeLayout: String, Equatable, Sendable {
    /// Sections + hairlines (Default / Sun Gold / Ink Night).
    case instrument
    /// Raised cards + metric grid.
    case bento

    var usesBentoLayout: Bool { self == .bento }
}
