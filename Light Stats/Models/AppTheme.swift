//
//  AppTheme.swift
//  Light Stats
//
//  Product preset ID only. Composition lives in `ThemeDefinition`.
//  Pure model: no SwiftUI, no tokens.
//

import Foundation

/// User-facing visual preset. Cold-start default is `.noir` (Ink Night / 墨夜).
/// `visibleCases` order is the picker display order: Default → Bento → Sun Gold → Ink Night.
/// Data Paper is temporarily hidden (`isVisible == false`), not deleted.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    /// System instrument readout. Display name: Default.
    case glass
    /// Raised bento cards / metric grid.
    case bento
    /// Sun Gold.
    case film
    /// Ink Night.
    case noir
    /// Data Paper.
    case dataPaper

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .glass: return "settings.theme.glass"
        case .bento: return "settings.theme.bento"
        case .film: return "settings.theme.film"
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
