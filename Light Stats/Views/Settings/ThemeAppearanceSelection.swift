//
//  ThemeAppearanceSelection.swift
//  Light Stats
//

import SwiftUI

extension GeneralDetail {
    @ViewBuilder
    var themeSectionContent: some View {
        switch settings.appTheme {
        case .film:
            staticThemeLayout(tokens: .film)
        case .noir:
            staticThemeLayout(tokens: .noir)
        case .bento, .glass:
            themeConfigurationControls
        }
    }
}
