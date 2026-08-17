//
//  ThemeAppearancePresetConfiguration.swift
//  Light Stats
//

import Foundation

struct ThemeAppearancePresetConfiguration: Sendable {
    let lightFlowValues: [Double]

    static let film = ThemeAppearancePresetConfiguration(
        lightFlowValues: [0, 0.2, 0.4, 0.65, 1]
    )

    static let noir = ThemeAppearancePresetConfiguration(
        lightFlowValues: [0, 0.2, 0.4, 0.65, 1]
    )
}
