import SwiftUI

struct FindMouseSettingsSection: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        SettingsGroup {
            SettingsRow(
                "settings.findMouse".localized,
                subtitle: "settings.findMouse.hint".localized
            ) {
                SettingsToggle(isOn: $settings.findMouseEnabled)
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
                .disabled(!settings.findMouseEnabled)
                .opacity(settings.findMouseEnabled ? 1 : 0.45)
            }
        }
    }
}
