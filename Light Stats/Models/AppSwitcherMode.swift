//
//  AppSwitcherMode.swift
//  Light Stats
//

import Foundation

/// How the ⌘Tab switcher presents the windows it offers.
///
/// Both modes read the same window list and commit through the same session; only the shape of the
/// panel and the meaning of "next" differ.
nonisolated enum AppSwitcherMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The system switcher's row of application icons, with a strip of that application's windows
    /// underneath. Tab moves between applications, the arrows move between their windows.
    case twoLevel
    /// One grid of every window, ordered by recency. Tab and the arrows all move the same selection.
    case grid

    var id: String { rawValue }

    /// A localization key, not a translated string: `String.localized` belongs to the view layer, and
    /// a model resolves nothing. Same shape as `AppTheme.titleKey`.
    var titleKey: String {
        switch self {
        case .twoLevel: return "settings.snap.switcherMode.twoLevel"
        case .grid: return "settings.snap.switcherMode.grid"
        }
    }
}
