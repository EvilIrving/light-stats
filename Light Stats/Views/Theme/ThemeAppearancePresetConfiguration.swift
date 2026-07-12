//
//  ThemeAppearancePresetConfiguration.swift
//  Light Stats
//

import Foundation

struct ThemeAppearancePresetConfiguration: Sendable {
    let flowValues: [Double]
    let positionValues: [Double]

    static let film = ThemeAppearancePresetConfiguration(
        flowValues: [0, 0.2, 0.4, 0.65, 1],
        positionValues: [0, 0.25, 0.5, 0.75, 1]
    )

    static let noir = ThemeAppearancePresetConfiguration(
        flowValues: [0, 0.2, 0.4, 0.65, 1],
        positionValues: [0, 0.25, 0.5, 0.75, 1]
    )
}
