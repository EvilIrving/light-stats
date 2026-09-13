import SwiftUI

/// 默认输入法：切换 App 后把输入源拉回用户选定的那一个。
/// 默认关闭（opt-in），与输入设备页其余扩展工具一致。
struct DefaultInputSourceSettingsSection: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject private var coordinator = DefaultInputSourceCoordinator.shared

    var body: some View {
        SettingsGroup {
            SettingsRow(
                "settings.defaultInputSource".localized,
                subtitle: "settings.defaultInputSource.hint".localized
            ) {
                HStack(spacing: 10) {
                    sourcePicker
                    SettingsToggle(isOn: $settings.defaultInputSourceEnabled)
                        .onChange(of: settings.defaultInputSourceEnabled) { _, isEnabled in
                            // 开启时以当前输入源兜底，用户不必先去选单里挑一次。
                            if isEnabled { coordinator.seedTargetFromCurrentSourceIfNeeded() }
                        }
                }
            }
        }
        .onAppear { coordinator.refreshAvailableSources() }
    }

    private var sourcePicker: some View {
        Picker("", selection: $settings.defaultInputSourceID) {
            if settings.defaultInputSourceID == nil {
                Text("settings.defaultInputSource.none".localized)
                    .tag(String?.none)
            }
            ForEach(pickerOptions) { option in
                Text(option.name).tag(Optional(option.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 168)
        .disabled(!settings.defaultInputSourceEnabled)
        .focusable(false)
    }

    /// 已选输入法被系统移除时，把它作为一个占位项留在选择器里。否则 `Picker` 找不到
    /// 匹配的 tag 会显示空白，用户看不出「为什么开了没反应」。
    static func pickerOptions(
        available: [InputSourceOption],
        storedID: String?,
        unavailableName: String
    ) -> [InputSourceOption] {
        guard let storedID, !available.contains(where: { $0.id == storedID }) else { return available }
        return [InputSourceOption(id: storedID, name: unavailableName)] + available
    }

    /// 已选输入法被系统移除时，把它作为一个占位项留在选择器里。
    private var pickerOptions: [InputSourceOption] {
        Self.pickerOptions(
            available: coordinator.availableSources,
            storedID: settings.defaultInputSourceID,
            unavailableName: "settings.defaultInputSource.unavailable".localized
        )
    }
}
