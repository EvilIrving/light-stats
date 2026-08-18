//
//  ThemeAppearanceSelection.swift
//  Light Stats
//

import SwiftUI

extension GeneralDetail {
    @ViewBuilder
    var themeAppearanceControls: some View {
        Group {
            switch settings.themeAppearance(for: settings.appTheme) {
            case .film:
                backgroundAppearanceControls(
                    grainEnabled: $settings.filmGrainEnabled,
                    lightFlow: $settings.filmLightFlow,
                    presets: .film
                )
            case .bar:
                backgroundAppearanceControls(
                    grainEnabled: $settings.barGrainEnabled,
                    lightFlow: $settings.barLightFlow,
                    presets: .bar
                )
            case .noir:
                backgroundAppearanceControls(
                    grainEnabled: $settings.noirGrainEnabled,
                    lightFlow: $settings.noirLightFlow,
                    presets: .noir
                )
            case .none:
                EmptyView()
            }
        }
        .id(settings.appTheme)
    }
}
