//
//  WindowManagementSettingsSection.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import SwiftUI

// MARK: - Window Management

struct WindowManagementDetail: View {
    @ObservedObject var settings: SettingsManager
    @StateObject private var systemTiling = SystemWindowTilingSettings()

    var body: some View {
        SettingsDetailScaffold("settings.windowManagement".localized) {
            SettingsGroup {
                SettingsRow(
                    "settings.windowManagement".localized,
                    subtitle: "settings.windowManagement.description".localized
                ) {
                    SettingsToggle(isOn: $settings.windowManagementEnabled)
                }
            }
            if #available(macOS 15.0, *) {
                SettingsSection("settings.systemTiling".localized) {
                    SettingsGroup {
                        SettingsRow(
                            "settings.systemTiling.edgeDrag".localized,
                            subtitle: "settings.systemTiling.description".localized
                        ) {
                            SettingsToggle(isOn: $systemTiling.edgeDragEnabled)
                        }
                        rowDivider()
                        SettingsRow("settings.systemTiling.topEdgeDrag".localized) {
                            SettingsToggle(isOn: $systemTiling.topEdgeDragEnabled)
                        }
                    }
                }
                .onAppear { systemTiling.reload() }
            }
        }
    }
}
