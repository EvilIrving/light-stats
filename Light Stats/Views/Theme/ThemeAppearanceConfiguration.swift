//
//  ThemeAppearanceConfiguration.swift
//  Light Stats
//

import Foundation

struct ThemeAppearanceConfiguration: Equatable, Sendable {
    let grainEnabled: Bool
    let dynamics: Double

    /// Natural light dynamics (segment value 0.4) for both mesh themes.
    static let defaultDynamics: Double = 0.4

    static func defaults(for _: AppTheme) -> ThemeAppearanceConfiguration {
        ThemeAppearanceConfiguration(
            grainEnabled: true,
            dynamics: defaultDynamics
        )
    }
}

extension SettingsManager {
    func themeAppearance(for theme: AppTheme) -> ThemeAppearanceConfiguration {
        switch theme {
        case .film:
            return ThemeAppearanceConfiguration(
                grainEnabled: filmGrainEnabled,
                dynamics: filmLightFlow
            )
        case .noir:
            return ThemeAppearanceConfiguration(
                grainEnabled: noirGrainEnabled,
                dynamics: noirLightFlow
            )
        default:
            return .defaults(for: theme)
        }
    }
}
