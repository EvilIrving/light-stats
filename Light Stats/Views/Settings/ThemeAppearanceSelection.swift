//
//  ThemeAppearanceSelection.swift
//  Light Stats
//

import SwiftUI

extension GeneralDetail {
    @ViewBuilder
    var themeAppearanceControls: some View {
        if settings.appTheme == .film {
            meshAppearanceControls(
                tokens: .film,
                grainEnabled: $settings.filmGrainEnabled,
                lightFlow: $settings.filmLightFlow,
                lightPositionX: $settings.filmLightPositionX,
                lightPositionY: $settings.filmLightPositionY,
                presets: .film
            )
        } else if settings.appTheme == .noir {
            meshAppearanceControls(
                tokens: .noir,
                grainEnabled: $settings.noirGrainEnabled,
                lightFlow: $settings.noirLightFlow,
                lightPositionX: $settings.noirLightPositionX,
                lightPositionY: $settings.noirLightPositionY,
                presets: .noir
            )
        }
    }
}
