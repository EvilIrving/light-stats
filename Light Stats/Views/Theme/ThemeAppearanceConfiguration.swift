//
//  ThemeAppearanceConfiguration.swift
//  Light Stats
//

import Foundation

struct ThemeAppearanceConfiguration: Equatable, Sendable {
    let grainEnabled: Bool
    let dynamics: Double

    /// Natural light dynamics (segment value 0.4) for both mesh backgrounds.
    static let defaultDynamics: Double = 0.4

    static let defaults = ThemeAppearanceConfiguration(
        grainEnabled: true,
        dynamics: defaultDynamics
    )
}

extension SettingsManager {
    func themeAppearance(for background: BackgroundConfiguration) -> ThemeAppearanceConfiguration {
        switch background.appearanceSlot {
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
        case nil:
            return .defaults
        }
    }
}
