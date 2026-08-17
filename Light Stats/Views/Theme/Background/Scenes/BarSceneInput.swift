//
//  BarSceneInput.swift
//  Light Stats
//

import Foundation

struct BarSceneInput: Equatable, Sendable {
    let grainEnabled: Bool
    let lightFlow: Double

    init(grainEnabled: Bool, lightFlow: Double) {
        self.grainEnabled = grainEnabled
        self.lightFlow = lightFlow
    }

    init(_ configuration: BarThemeAppearanceConfiguration) {
        self.init(
            grainEnabled: configuration.grainEnabled,
            lightFlow: configuration.lightFlow
        )
    }

    static let defaults = BarSceneInput(.defaults)
}
