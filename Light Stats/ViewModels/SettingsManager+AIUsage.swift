//
//  SettingsManager+AIUsage.swift
//  Light Stats
//
//  Static helpers only. Instance storage and `defaults` stay in SettingsManager.swift
//  because Swift `private` / `private(set)` is file-scoped.
//

import Foundation

extension SettingsManager {
    static func aiMonitorEnabledKey(for id: AIProvider) -> String {
        "settings.aiMonitor.\(id.rawValue).enabled"
    }

    /// Migrates legacy per-vendor Bool keys when the new keyed flag is absent,
    /// then reads the enabled set. Never writes `false`. Never calls
    /// `setAIProviderEnabled`.
    static func migrateAndReadEnabledAIProviders(from defaults: UserDefaults) -> Set<AIProvider> {
        let legacy: [AIProvider: String] = [
            .claude: "settings.aiMonitorClaude",
            .codex: "settings.aiMonitorCodex",
            .gemini: "settings.aiMonitorGemini"
        ]
        for id in AIProvider.allCases {
            let newKey = aiMonitorEnabledKey(for: id)
            guard defaults.object(forKey: newKey) == nil,
                  let oldKey = legacy[id],
                  let old = defaults.object(forKey: oldKey) as? Bool else { continue }
            defaults.set(old, forKey: newKey)
        }
        var enabled = Set<AIProvider>()
        for id in AIProvider.allCases where defaults.object(forKey: aiMonitorEnabledKey(for: id)) as? Bool == true {
            enabled.insert(id)
        }
        return enabled
    }
}
