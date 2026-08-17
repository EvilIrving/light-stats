//
//  ThemeEnvironment.swift
//  Light Stats
//
//  Environment injection for UITokens + view helper that applies
//  preferredColorScheme / tint from the resolved ThemeDefinition.
//

import SwiftUI

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = UITokens.glass
}

private struct ThemeLayoutKey: EnvironmentKey {
    static let defaultValue = ThemeLayout.instrument
}

extension EnvironmentValues {
    var theme: UITokens {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }

    var themeLayout: ThemeLayout {
        get { self[ThemeLayoutKey.self] }
        set { self[ThemeLayoutKey.self] = newValue }
    }
}

// MARK: - Apply theme

extension View {
    /// Resolves `ThemeDefinition` for the product preset and injects UI tokens.
    func appThemed(_ theme: AppTheme) -> some View {
        let definition = ThemeDefinition.definition(for: theme)
        return self
            .environment(\.theme, definition.ui)
            .environment(\.themeLayout, definition.layout)
            .preferredColorScheme(definition.ui.preferredColorScheme)
            .tint(definition.ui.accent)
    }
}
