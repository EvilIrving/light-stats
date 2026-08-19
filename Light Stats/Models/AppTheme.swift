//
//  AppTheme.swift
//  Light Stats
//
//  Product preset ID only. Composition lives in `ThemeDefinition`.
//  Pure model: no SwiftUI, no tokens.
//

import Foundation

/// User-facing visual preset. Cold-start default is `.noir` (Ink Night / 墨夜).
/// `visibleCases` order is the picker display order:
/// Default → Orange Sea → Night Bar → Ink Night.
/// Data Paper is temporarily hidden (`isVisible == false`), not deleted.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    /// System instrument readout. Display name: Default.
    case glass
    /// Orange Sea — warm brass chrome over the Sun Gold field.
    case film
    /// Night Bar — espresso-black cocktail bar with warm amber light and
    /// a single cool teal neon accent.
    case bar
    /// Ink Night.
    case noir
    /// Data Paper.
    case dataPaper

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .glass: return "settings.theme.glass"
        case .film: return "settings.theme.film"
        case .bar: return "settings.theme.bar"
        case .noir: return "settings.theme.noir"
        case .dataPaper: return "settings.theme.dataPaper"
        }
    }

    /// Whether the theme is offered to users in the picker.
    /// `dataPaper` is temporarily hidden (show = false) but stays in the enum
    /// so its composition and rendering code remain intact.
    var isVisible: Bool { self != .dataPaper }

    /// Themes shown in the picker, in display order.
    static var visibleCases: [AppTheme] { allCases.filter(\.isVisible) }

    /// Resolve from UserDefaults. Missing, unknown, or hidden keys → `.noir`.
    /// A previously stored hidden theme resolves to `.noir` so it never stays applied.
    static func resolve(stored raw: String?) -> AppTheme {
        guard let raw else { return .noir }
        let resolved = AppTheme(rawValue: raw) ?? .noir
        return resolved.isVisible ? resolved : .noir
    }
}
