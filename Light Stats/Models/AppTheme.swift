//
//  AppTheme.swift
//  Light Stats
//
//  User-selectable visual theme for the app UI (popover, settings, about, etc.).
//  Pure model: no SwiftUI, no tokens — tokens live in Views/Theme.
//

import Foundation

/// App-wide visual theme. Cold-start default is `.noir` (Ink Night / 墨夜).
/// On macOS 26+ this uses Liquid Glass vibrancy; on macOS 15 it is ordinary system chrome.
/// `allCases` order is the picker display order: Default → Bento → Sun Gold → Ink Night.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    /// System instrument readout (no card chrome). Display name: Default.
    case glass
    /// Original Light Stats look: Liquid Glass + rounded bento cards / metric grid.
    case bento
    /// Sun Gold: warm grain mesh with coral and wine light fields.
    case film
    /// Ink Night: ink-black grain mesh with cool charcoal light fields.
    case noir

    var id: String { rawValue }

    /// True when Overview / Cleanup should use the classic card grid chrome.
    var usesBentoLayout: Bool { self == .bento }

    var titleKey: String {
        switch self {
        case .glass: return "settings.theme.glass"
        case .bento: return "settings.theme.bento"
        case .film: return "settings.theme.film"
        case .noir: return "settings.theme.noir"
        }
    }

    /// Resolve from UserDefaults. Cold start and unknown keys → `.noir`.
    /// Retired keys (`aurora`, `paper`) map to `.film` (their historical mesh look).
    static func resolve(stored raw: String?) -> AppTheme {
        guard let raw else { return .noir }
        if raw == "aurora" || raw == "paper" { return .film }
        return AppTheme(rawValue: raw) ?? .noir
    }
}
