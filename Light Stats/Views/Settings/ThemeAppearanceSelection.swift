//
//  ThemeAppearanceSelection.swift
//  Light Stats
//

import SwiftUI

extension GeneralDetail {
    @ViewBuilder
    var themeSectionContent: some View {
        let definition = ThemeDefinition.definition(for: settings.appTheme)
        if definition.background == .systemGlass {
            themeConfigurationControls
        } else {
            themeWithPreviewLayout(sceneID: definition.background)
        }
    }

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
