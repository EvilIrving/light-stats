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
                    SettingsToggle(isOn: $settings.findMouseEnabled)
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
            Divider().padding(.leading, 12)
            SettingsRow("settings.findMouseTriggerKey".localized) {
                SettingsSegmentedPicker(
                    selection: $settings.findMouseTriggerKey,
                    segmentMinWidth: 36
                ) {
                    ForEach(FindMouseTriggerKey.allCases, id: \.self) { key in
                        SettingsSegmentLabel(title: key.symbol).tag(key)
                    }
                }
            }
            .disabled(!settings.findMouseEnabled || !license.isFindMouseUnlocked)
            .opacity((settings.findMouseEnabled && license.isFindMouseUnlocked) ? 1 : 0.45)
        }
    }
}
