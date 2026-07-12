//
//  ThemeAppearanceConfiguration.swift
//  Light Stats
//

import Foundation

struct ThemeAppearanceConfiguration: Equatable, Sendable {
    let grainEnabled: Bool
    let lightFlow: Double
    let lightPositionX: Double
    let lightPositionY: Double

    static func defaults(for theme: AppTheme) -> ThemeAppearanceConfiguration {
        ThemeAppearanceConfiguration(
            grainEnabled: true,
            lightFlow: theme == .noir ? 0.25 : 0.5,
            lightPositionX: 0.5,
            lightPositionY: 0.5
        )
    }
}

extension SettingsManager {
    func themeAppearance(for theme: AppTheme) -> ThemeAppearanceConfiguration {
        switch theme {
        case .film:
            return ThemeAppearanceConfiguration(
                grainEnabled: filmGrainEnabled,
                lightFlow: filmLightFlow,
                lightPositionX: filmLightPositionX,
                lightPositionY: filmLightPositionY
            )
        case .noir:
            return ThemeAppearanceConfiguration(
                grainEnabled: noirGrainEnabled,
                lightFlow: noirLightFlow,
                lightPositionX: noirLightPositionX,
                lightPositionY: noirLightPositionY
            )
        default:
            return .defaults(for: theme)
        }
    }
}
