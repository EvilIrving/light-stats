//
//  ThemeAppearanceConfiguration.swift
//  Light Stats
//

import Foundation

enum ThemeAppearanceConfiguration: Equatable, Sendable {
    case none
    case film(FilmThemeAppearanceConfiguration)
    case noir(NoirThemeAppearanceConfiguration)
}

extension SettingsManager {
    func themeAppearance(for theme: AppTheme) -> ThemeAppearanceConfiguration {
        switch theme {
        case .glass, .bento, .dataPaper:
            return .none
        case .film:
            return .film(FilmThemeAppearanceConfiguration(
                grainEnabled: filmGrainEnabled,
                lightFlow: filmLightFlow
            ))
        case .noir:
            return .noir(NoirThemeAppearanceConfiguration(
                grainEnabled: noirGrainEnabled,
                lightFlow: noirLightFlow
            ))
        }
    }
}
