//
//  ThemeEnvironment.swift
//  Light Stats
//
//  Environment injection for ThemeTokens + view helper that applies
//  preferredColorScheme / tint from the selected AppTheme.
//

import SwiftUI

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeTokens.film
}

extension EnvironmentValues {
    var theme: ThemeTokens {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Apply theme

extension View {
    /// Injects theme tokens, forces color scheme when the theme demands it,
    /// and tints interactive controls with the theme accent.
    func appThemed(_ theme: AppTheme) -> some View {
        let tokens = ThemeTokens.tokens(for: theme)
        return self
            .environment(\.theme, tokens)
            .preferredColorScheme(tokens.preferredColorScheme)
            .tint(tokens.accent)
    }
}
