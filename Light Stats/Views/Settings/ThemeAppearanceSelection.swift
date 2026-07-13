//
//  ThemeAppearanceSelection.swift
//  Light Stats
//

import SwiftUI

extension GeneralDetail {
    @ViewBuilder
    var themeSectionContent: some View {
        if settings.appTheme == .film {
            meshThemeLayout(tokens: .film)
        } else if settings.appTheme == .noir {
            meshThemeLayout(tokens: .noir)
        } else {
            themeConfigurationControls
        }
    }

    @ViewBuilder
    var themeAppearanceControls: some View {
        Group {
            if settings.appTheme == .film {
                meshAppearanceControls(
                    grainEnabled: $settings.filmGrainEnabled,
                    dynamics: $settings.filmLightFlow,
                    presets: .film
                )
            } else if settings.appTheme == .noir {
                meshAppearanceControls(
                    grainEnabled: $settings.noirGrainEnabled,
                    dynamics: $settings.noirLightFlow,
                    presets: .noir
                )
            }
        }
        .id(settings.appTheme)
    }
}
