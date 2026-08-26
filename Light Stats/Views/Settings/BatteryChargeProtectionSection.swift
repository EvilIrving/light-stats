import SwiftUI

struct BatteryChargeProtectionSection: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject private var batteryControlManager = BatteryChargeControlManager.shared

    var body: some View {
        if DeviceCapabilities.isPortable {
            SettingsSection("settings.batteryProtection.section".localized) {
                SettingsGroup {
                    SettingsRow(
                        "settings.batteryProtection.enabled".localized,
                        subtitle: "settings.batteryProtection.hint".localized
                    ) {
                        HStack(spacing: 10) {
                            SettingsToggle(isOn: $settings.batteryChargeControlEnabled)
                            BatteryChargeRangeSlider(
                                lowerValue: $settings.batteryChargeLowerLimit,
                                upperValue: $settings.batteryChargeUpperLimit
                            )
                            .frame(width: 260)
                        }
                    }
                    if settings.batteryChargeControlEnabled,
                       let message = batteryControlManager.snapshot.errorMessage,
                       !message.isEmpty {
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                }
                Text("settings.batteryProtection.helperHint".localized)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
