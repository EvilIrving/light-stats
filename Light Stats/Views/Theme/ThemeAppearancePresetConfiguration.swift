//
//  ThemeAppearancePresetConfiguration.swift
//  Light Stats
//

import Foundation

struct ThemeAppearancePresetConfiguration: Sendable {
    let dynamicsValues: [Double]

    static let film = ThemeAppearancePresetConfiguration(
        dynamicsValues: [0, 0.2, 0.4, 0.65, 1]
    )

    static let noir = ThemeAppearancePresetConfiguration(
        dynamicsValues: [0, 0.2, 0.4, 0.65, 1]
    )
}
