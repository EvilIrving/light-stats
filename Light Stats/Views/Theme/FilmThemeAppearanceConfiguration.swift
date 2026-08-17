//
//  FilmThemeAppearanceConfiguration.swift
//  Light Stats
//

import Foundation

struct FilmThemeAppearanceConfiguration: Equatable, Sendable {
    let grainEnabled: Bool
    let lightFlow: Double

    static let defaults = FilmThemeAppearanceConfiguration(
        grainEnabled: true,
        lightFlow: 0.4
    )
}
