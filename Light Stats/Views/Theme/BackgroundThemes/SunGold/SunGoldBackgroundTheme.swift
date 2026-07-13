//
//  SunGoldBackgroundTheme.swift
//  Light Stats
//

import Foundation

/// Composition root for the complete Sun Gold scene module.
enum SunGoldBackgroundTheme {
    static let definition: BackgroundThemeDefinition = {
        let palette = Palette()
        return BackgroundThemeDefinition(
            identifier: "sun-gold-background",
            sceneModel: SunGoldSceneModel(palette: palette),
            occlusionModel: SunGoldTreeShadowModel(palette: palette),
            readabilityPolicy: SunGoldReadabilityPolicy(palette: palette),
            materialEffects: [
                AnyBackgroundMaterialEffect(
                    GrainBackgroundMaterial(
                        identifier: "sun-gold-grain",
                        opacity: 0.25,
                        warmth: 0.62
                    )
                ),
                AnyBackgroundMaterialEffect(
                    FilmVignetteBackgroundMaterial(
                        identifier: "sun-gold-film-vignette",
                        tint: palette.vignette,
                        opacity: 0.16
                    )
                )
            ]
        )
    }()

    struct Palette: Sendable {
        let base = BackgroundSceneFrame.Color(red: 0.15, green: 0.065, blue: 0.045)
        let sunCore = BackgroundSceneFrame.Color(red: 1.0, green: 0.52, blue: 0.28)
        let sunEdge = BackgroundSceneFrame.Color(red: 0.78, green: 0.14, blue: 0.09)
        let treeShadow = BackgroundSceneFrame.Color(red: 0.045, green: 0.024, blue: 0.018)
        let readingInk = BackgroundSceneFrame.Color(red: 0.07, green: 0.03, blue: 0.025)
        let vignette = BackgroundSceneFrame.Color(red: 0.32, green: 0.11, blue: 0.06)
    }
}
