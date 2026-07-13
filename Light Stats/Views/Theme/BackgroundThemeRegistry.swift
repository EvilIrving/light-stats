//
//  BackgroundThemeRegistry.swift
//  Light Stats
//

import Foundation

/// The only application composition entry that maps persisted themes to backgrounds.
enum BackgroundThemeRegistry {
    static func definition(for theme: AppTheme) -> BackgroundThemeDefinition? {
        registrations[theme]
    }

    private static let registrations: [AppTheme: BackgroundThemeDefinition] = [
        .film: SunGoldBackgroundTheme.definition,
        .noir: InkNightBackgroundTheme.definition
    ]
}
