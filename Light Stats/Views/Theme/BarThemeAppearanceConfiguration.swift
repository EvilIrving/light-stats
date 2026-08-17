//
//  BarThemeAppearanceConfiguration.swift
//  Light Stats
//

import Foundation

struct BarThemeAppearanceConfiguration: Equatable, Sendable {
    let grainEnabled: Bool
    let lightFlow: Double

    static let defaults = BarThemeAppearanceConfiguration(
        grainEnabled: true,
        lightFlow: 0.4
    )
}
