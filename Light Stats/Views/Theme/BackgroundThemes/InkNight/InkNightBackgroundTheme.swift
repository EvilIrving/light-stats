//
//  InkNightBackgroundTheme.swift
//  Light Stats
//

import Foundation

/// Composition root for the complete Ink Night scene module.
enum InkNightBackgroundTheme {
    static let definition: BackgroundThemeDefinition = {
        let palette = Palette()
        return BackgroundThemeDefinition(
            identifier: "ink-night-background",
            sceneModel: InkNightSceneModel(palette: palette),
            occlusionModel: InkNightCloudOcclusionModel(palette: palette),
            readabilityPolicy: InkNightReadabilityPolicy(palette: palette),
            materialEffects: [
                AnyBackgroundMaterialEffect(
                    GrainBackgroundMaterial(
                        identifier: "ink-night-grain",
                        opacity: 0.22,
                        warmth: 0
                    )
                ),
                AnyBackgroundMaterialEffect(
                    FilmVignetteBackgroundMaterial(
                        identifier: "ink-night-film-vignette",
                        tint: palette.vignette,
                        opacity: 0.18
                    )
                )
            ]
        )
    }()

    struct Palette: Sendable {
        let base = BackgroundSceneFrame.Color(red: 0.025, green: 0.028, blue: 0.052)
        let moonCore = BackgroundSceneFrame.Color(red: 0.68, green: 0.73, blue: 0.91)
        let moonlight = BackgroundSceneFrame.Color(red: 0.39, green: 0.46, blue: 0.70)
        let cloud = BackgroundSceneFrame.Color(red: 0.026, green: 0.031, blue: 0.061)
        let cloudSilver = BackgroundSceneFrame.Color(red: 0.45, green: 0.52, blue: 0.76)
        let readingInk = BackgroundSceneFrame.Color(red: 0.015, green: 0.018, blue: 0.035)
        let vignette = BackgroundSceneFrame.Color(red: 0.07, green: 0.08, blue: 0.16)
    }
}
