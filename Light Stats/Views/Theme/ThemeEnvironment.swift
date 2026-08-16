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

extension EnvironmentValues {
    var theme: UITokens {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Apply theme

extension View {
    /// Resolves `ThemeDefinition` for the product preset and injects UI tokens.
    func appThemed(_ theme: AppTheme) -> some View {
        let tokens = ThemeDefinition.definition(for: theme).ui
        return self
            .environment(\.theme, tokens)
            .preferredColorScheme(tokens.preferredColorScheme)
            .tint(tokens.accent)
    }
}
