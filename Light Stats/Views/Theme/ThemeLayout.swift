//
//  ThemeLayout.swift
//  Light Stats
//
//  Overview / Cleanup chrome: sections + hairlines. Resolved by
//  `ThemeDefinition`, not by comparing `AppTheme` cases in business views.
//

import Foundation

enum ThemeLayout: String, Equatable, Sendable {
    /// Sections + hairlines (Default / Sun Gold / Ink Night).
    case instrument
}
