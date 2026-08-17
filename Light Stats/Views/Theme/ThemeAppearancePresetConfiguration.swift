//
//  ThemeAppearancePresetConfiguration.swift
//  Light Stats
//

import Foundation

struct ThemeAppearancePresetConfiguration: Sendable {
    let lightFlowValues: [Double]

    static let film = ThemeAppearancePresetConfiguration(
        lightFlowValues: [0, 0.4, 1]
    )

    static let bar = ThemeAppearancePresetConfiguration(
        lightFlowValues: [0, 0.4, 1]
    )

    static let noir = ThemeAppearancePresetConfiguration(
        lightFlowValues: [0, 0.4, 1]
    )
}
