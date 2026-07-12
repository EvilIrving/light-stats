//
//  ThemeAppearanceSelection.swift
//  Light Stats
//

import SwiftUI

extension GeneralDetail {
    @ViewBuilder
    var themeAppearanceControls: some View {
        Group {
            if settings.appTheme == .film {
                meshAppearanceControls(
                    tokens: .film,
                    grainEnabled: $settings.filmGrainEnabled,
                    dynamics: $settings.filmLightFlow,
                    presets: .film
                )
            } else if settings.appTheme == .noir {
                meshAppearanceControls(
                    tokens: .noir,
                    grainEnabled: $settings.noirGrainEnabled,
                    dynamics: $settings.noirLightFlow,
                    presets: .noir
                )
            }
        }
        .id(settings.appTheme)
    }
}
