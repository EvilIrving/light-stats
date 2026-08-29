import SwiftUI

struct FindMouseSettingsSection: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject private var license = LicenseManager.shared
    /// 未激活时点击「激活」跳转到激活分类。
    var onRequestActivation: () -> Void = {}

    var body: some View {
        SettingsGroup {
            if license.isFindMouseUnlocked {
                SettingsRow(
                    "settings.findMouse".localized,
                    subtitle: "settings.findMouse.hint".localized
                ) {
                    HStack(spacing: 10) {
                        SettingsToggle(isOn: $settings.findMouseEnabled)

                        FindMouseTriggerRecorder(
                            selection: $settings.findMouseTriggerKey,
                            isEnabled: settings.findMouseEnabled
                        )
                    }
                }
            } else {
                SettingsRow(
                    "settings.findMouse".localized,
                    subtitle: "settings.findMouse.lockedHint".localized
                ) {
                    Button("settings.activation.activate".localized, action: onRequestActivation)
                        .controlSize(.regular)
                }
            }
        }
    }
}
