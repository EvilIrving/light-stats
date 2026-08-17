//
//  NoirThemeAppearanceConfiguration.swift
//  Light Stats
//

import Foundation

struct NoirThemeAppearanceConfiguration: Equatable, Sendable {
    let grainEnabled: Bool
    let lightFlow: Double

    static let defaults = NoirThemeAppearanceConfiguration(
        grainEnabled: true,
        lightFlow: 0.4
    )
}
