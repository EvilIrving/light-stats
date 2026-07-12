//
//  AppTheme.swift
//  Light Stats
//
//  User-selectable visual theme for the app UI (popover, settings, about, etc.).
//  Pure model: no SwiftUI, no tokens — tokens live in Views/Theme.
//

import Foundation

/// App-wide visual theme. Default is `.film` (胶片棕 — warm grain mesh).
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    /// Warm film-stock brown grain mesh. Cold-start default.
    case film
    /// Original Light Stats look: Liquid Glass + rounded bento cards / metric grid.
    case bento
    /// System vibrancy / Liquid Glass — instrument readout (no card chrome).
    case glass
    /// Near-black grainy mesh; deep charcoal surfaces.
    case noir

    var id: String { rawValue }

    /// True when Overview / Cleanup should use the classic card grid chrome.
    var usesBentoLayout: Bool { self == .bento }

    var titleKey: String {
        switch self {
        case .film: return "settings.theme.film"
        case .bento: return "settings.theme.bento"
        case .glass: return "settings.theme.glass"
        case .noir: return "settings.theme.noir"
        }
    }

    var subtitleKey: String {
        switch self {
        case .film: return "settings.theme.film.hint"
        case .bento: return "settings.theme.bento.hint"
        case .glass: return "settings.theme.glass.hint"
        case .noir: return "settings.theme.noir.hint"
        }
    }

    /// Resolve from UserDefaults. Maps retired keys (`aurora`, `paper`) to `.film`.
    static func resolve(stored raw: String?) -> AppTheme {
        guard let raw else { return .film }
        if raw == "aurora" || raw == "paper" { return .film }
        return AppTheme(rawValue: raw) ?? .film
    }
}
