//
//  SunGoldSceneInput.swift
//  Light Stats
//

import Foundation

struct SunGoldSceneInput: Equatable, Sendable {
    let grainEnabled: Bool
    let lightFlow: Double

    init(grainEnabled: Bool, lightFlow: Double) {
        self.grainEnabled = grainEnabled
        self.lightFlow = lightFlow
    }

    init(_ configuration: FilmThemeAppearanceConfiguration) {
        self.init(
            grainEnabled: configuration.grainEnabled,
            lightFlow: configuration.lightFlow
        )
    }

    static let defaults = SunGoldSceneInput(.defaults)
}
