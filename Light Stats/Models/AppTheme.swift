//
//  AppTheme.swift
//  Light Stats
//
//  Product preset ID only. Composition lives in `ThemeDefinition`.
//  Pure model: no SwiftUI, no tokens.
//

import Foundation

/// User-facing visual preset. Cold-start default is `.noir` (Ink Night / 墨夜).
/// `allCases` order is the picker display order: Default → Bento → Sun Gold → Ink Night.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    /// System instrument readout. Display name: Default.
    case glass
    /// Raised bento cards / metric grid.
    case bento
    /// Sun Gold.
    case film
    /// Ink Night.
    case noir

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .glass: return "settings.theme.glass"
        case .bento: return "settings.theme.bento"
        case .film: return "settings.theme.film"
        case .noir: return "settings.theme.noir"
        }
    }

    /// Resolve from UserDefaults. Missing or unknown keys → `.noir`.
    static func resolve(stored raw: String?) -> AppTheme {
        guard let raw else { return .noir }
        return AppTheme(rawValue: raw) ?? .noir
    }
}
