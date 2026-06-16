//
//  LocalizationManager.swift
//  Light Stats
//
//  Created on 2026/01/16.
//

import Foundation
import SwiftUI
import Combine

/// Supported app languages
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"
    case ja = "ja"
    case ko = "ko"

    var id: String { rawValue }

    /// Display name for the language (always in native language)
    nonisolated var displayName: String {
        switch self {
        case .system: return String(localized: "language.system")
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }

    /// Get the actual locale identifier
    nonisolated var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "zh-Hans"
        case .en: return "en"
        case .ja: return "ja"
        case .ko: return "ko"
        }
    }
}

/// Manages app localization and language switching
@MainActor
final class LocalizationManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = LocalizationManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var currentLocale: Locale
    @Published private(set) var currentLanguage: AppLanguage
    
    // MARK: - Private Properties
    
    private let userDefaultsKey = "settings.appLanguage"
    
    // MARK: - Init
    
    private init() {
        // Load saved language preference
        let savedLanguage = UserDefaults.standard.string(forKey: userDefaultsKey) ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: savedLanguage) ?? .system
        
        self.currentLanguage = language
        self.currentLocale = LocalizationManager.resolveLocale(for: language)
    }
    
    // MARK: - Public Methods
    
    /// Set the app language
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        currentLocale = LocalizationManager.resolveLocale(for: language)

        // Persist the setting
        UserDefaults.standard.set(language.rawValue, forKey: userDefaultsKey)
    }
    
    /// Get localized string for a key. Thread-safe: reads language from UserDefaults.
    nonisolated func localizedString(_ key: String) -> String {
        Self.localizedString(key)
    }

    /// Get localized string with format arguments
    nonisolated func localizedString(_ key: String, _ args: CVarArg...) -> String {
        Self.localizedString(key, args)
    }

    /// Get localized string for a key without touching MainActor state.
    nonisolated static func localizedString(_ key: String) -> String {
        let savedLanguage = UserDefaults.standard.string(forKey: "settings.appLanguage") ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: savedLanguage) ?? .system

        guard let localeIdentifier = language.localeIdentifier else {
            return NSLocalizedString(key, comment: "")
        }

        guard let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }

        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Get localized string with format arguments without touching MainActor state.
    nonisolated static func localizedString(_ key: String, _ args: CVarArg...) -> String {
        let format = localizedString(key)
        return String(format: format, arguments: args)
    }
    
    // MARK: - Private Methods
    
    private static func resolveLocale(for language: AppLanguage) -> Locale {
        switch language {
        case .system:
            return Locale.current
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .en:
            return Locale(identifier: "en")
        case .ja:
            return Locale(identifier: "ja")
        case .ko:
            return Locale(identifier: "ko")
        }
    }
}

// MARK: - SwiftUI Environment Key

private struct LocalizationManagerKey: EnvironmentKey {
    nonisolated static let defaultValue: LocalizationManager = MainActor.assumeIsolated { LocalizationManager.shared }
}

extension EnvironmentValues {
    var localizationManager: LocalizationManager {
        get { self[LocalizationManagerKey.self] }
        set { self[LocalizationManagerKey.self] = newValue }
    }
}

// MARK: - String Extension for Localization

extension String {
    /// Get localized string using LocalizationManager
    nonisolated var localized: String {
        LocalizationManager.localizedString(self)
    }

    /// Get localized string with format arguments
    nonisolated func localized(_ args: CVarArg...) -> String {
        let format = LocalizationManager.localizedString(self)
        return String(format: format, arguments: args)
    }
}

// MARK: - View Extension

extension View {
    /// Apply the current locale from LocalizationManager
    @MainActor
    func withLocalization() -> some View {
        self.environment(\.locale, LocalizationManager.shared.currentLocale)
    }
}
