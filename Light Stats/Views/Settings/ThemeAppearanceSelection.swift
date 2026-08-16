//
//  ThemeAppearanceSelection.swift
//  Light Stats
//

import SwiftUI

extension GeneralDetail {
    @ViewBuilder
    var themeSectionContent: some View {
        let definition = ThemeDefinition.definition(for: settings.appTheme)
        if definition.background.kind == .mesh {
            meshThemeLayout(configuration: definition.background)
        } else {
            themeConfigurationControls
        }
    }

    @ViewBuilder
    var themeAppearanceControls: some View {
        let definition = ThemeDefinition.definition(for: settings.appTheme)
        Group {
            switch definition.background.appearanceSlot {
            case .film:
                meshAppearanceControls(
                    grainEnabled: $settings.filmGrainEnabled,
                    dynamics: $settings.filmLightFlow,
                    presets: .film
                )
            case .noir:
                meshAppearanceControls(
                    grainEnabled: $settings.noirGrainEnabled,
                    dynamics: $settings.noirLightFlow,
                    presets: .noir
                )
            case nil:
                EmptyView()
            }
        }
        .id(settings.appTheme)
    }
}
