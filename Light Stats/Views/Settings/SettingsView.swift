//
//  SettingsView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var showMinimumItemAlert = false
    @State private var showExitPrivacyAlert = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // 1. Status Bar Items Card
                BentoCard(title: "settings.statusBar".localized) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        SettingsGridItem(
                            title: "settings.logo".localized,
                            isOn: $settings.showLogo,
                            icon: "applelogo",
                            assetIcon: "StatusIcon"
                        ) {
                            validateMinimumItems()
                        }
                        SettingsGridItem(title: "settings.cpu".localized, isOn: $settings.showCPU, icon: "cpu") {
                            validateMinimumItems()
                        }
                        SettingsGridItem(title: "settings.gpu".localized, isOn: $settings.showGPU, icon: "square.grid.2x2") {
                            validateMinimumItems()
                        }
                        SettingsGridItem(title: "settings.memory".localized, isOn: $settings.showMemory, icon: "memorychip") {
                            validateMinimumItems()
                        }
                        SettingsGridItem(title: "settings.disk".localized, isOn: $settings.showDisk, icon: "internaldrive") {
                            validateMinimumItems()
                        }
                        SettingsGridItem(title: "settings.network".localized, isOn: $settings.showNetwork, icon: "network") {
                            validateMinimumItems()
                        }
                        SettingsGridItem(title: "settings.fan".localized, isOn: $settings.showFan, icon: "fanblades") {
                            validateMinimumItems()
                        }
                        SettingsGridItem(title: "settings.battery".localized, isOn: $settings.showBattery, icon: "battery.100") {
                            validateMinimumItems()
                        }
                        SettingsGridItem(title: "settings.health".localized, isOn: $settings.showHealth, icon: "heart.text.square") {
                            validateMinimumItems()
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 2. Appearance Card — 平缓色调 + 语言
                BentoCard(title: "settings.appearance".localized) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("settings.flatColors.section".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: $settings.useFlatColors)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        HStack {
                            Text("settings.language".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.appLanguage) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(lang.shortName).tag(lang)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }

                // 3. Health Score Card — 颜色指示器开关在标题栏，维度网格在正文。
                BentoCard(title: "settings.health".localized,
                          headerAccessory: {
                    Toggle("", isOn: $settings.useColorIndicator)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        HealthDimButton(
                            title: "health.dimension.cpu".localized,
                            isOn: $settings.healthIncludeCPU,
                            demoLevel: .low, useColorIndicator: settings.useColorIndicator
                        )
                        HealthDimButton(
                            title: "health.dimension.memory".localized,
                            isOn: $settings.healthIncludeMemory,
                            demoLevel: .low, useColorIndicator: settings.useColorIndicator
                        )
                        HealthDimButton(
                            title: "health.dimension.load".localized,
                            isOn: $settings.healthIncludeLoad,
                            demoLevel: .medium, useColorIndicator: settings.useColorIndicator
                        )
                        HealthDimButton(
                            title: "health.dimension.temperature".localized,
                            isOn: $settings.healthIncludeTemperature,
                            demoLevel: .high, useColorIndicator: settings.useColorIndicator
                        )
                        HealthDimButton(
                            title: "health.dimension.gpu".localized,
                            isOn: $settings.healthIncludeGPU,
                            demoLevel: .medium, useColorIndicator: settings.useColorIndicator
                        )
                        HealthDimButton(
                            title: "settings.healthDimensions.power".localized,
                            isOn: $settings.healthIncludePower,
                            demoLevel: .low, useColorIndicator: settings.useColorIndicator
                        )
                    }
                    .padding(.vertical, 4)
                }

                // 4. Refresh & Units Card
                BentoCard(title: "settings.refreshAndUnits".localized) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("settings.refreshRate.label".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.refreshRate) {
                                ForEach(SettingsManager.RefreshRate.allCases, id: \.self) { rate in
                                    Text(rate.displayName).tag(rate)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }

                        HStack {
                            Text("settings.temperatureUnit".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.temperatureUnit) {
                                ForEach(SettingsManager.TemperatureUnit.allCases, id: \.self) { unit in
                                    Text(unit.displayName).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        HStack {
                            Text("settings.networkSpeedUnit".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.networkSpeedUnit) {
                                ForEach(SettingsManager.NetworkSpeedUnit.allCases, id: \.self) { unit in
                                    Text(unit.displayName).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                }

                // 5. AI Usage Card
                BentoCard(title: "settings.aiUsage".localized) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("aiUsage.claude".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: $settings.aiMonitorClaudeEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        HStack {
                            Text("aiUsage.codex".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: $settings.aiMonitorCodexEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        HStack {
                            Text("aiUsage.gemini".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: $settings.aiMonitorGeminiEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        if settings.aiMonitorClaudeEnabled || settings.aiMonitorCodexEnabled || settings.aiMonitorGeminiEnabled {
                            HStack {
                                Text("settings.aiUsageInterval".localized)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(SettingsManager.AIRefreshInterval.m2.displayName)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 6. Exit Node Card
                BentoCard(title: "settings.exitNode.section".localized,
                          headerAccessory: {
                    Toggle("", isOn: Binding(
                        get: { settings.exitNodeDetectionEnabled },
                        set: { newValue in
                            if newValue {
                                showExitPrivacyAlert = true
                            } else {
                                settings.exitNodeDetectionEnabled = false
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }) {
                    if settings.exitNodeDetectionEnabled {
                        HStack {
                            Text("settings.exitNode.provider".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.exitNodeProvider) {
                                ForEach(ExitNodeProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 140)
                        }
                    }
                }

                // 7. Software Update Card
                BentoCard(title: "settings.update.section".localized,
                          headerAccessory: {
                    Toggle("", isOn: $settings.autoCheckUpdates)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }) {
                    Button {
                        UpdateManager.shared.checkForUpdates(userInitiated: true)
                    } label: {
                        Text("update.checkButton".localized)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
            }
            .padding(16)
        }
        .frame(width: 430, height: 676)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("settings.minimumItemAlert".localized, isPresented: $showMinimumItemAlert) {
            Button("settings.ok".localized, role: .cancel) {}
        }
        .alert("settings.exitNode.privacyTitle".localized, isPresented: $showExitPrivacyAlert) {
            Button("settings.exitNode.cancel".localized, role: .cancel) {}
            Button("settings.exitNode.enable".localized) {
                settings.exitNodeDetectionEnabled = true
            }
        } message: {
            Text("settings.exitNode.privacyMessage".localized)
        }
        .id(localization.currentLanguage)
        // Globally suppress the blue keyboard focus ring (e.g. on the segmented
        // language picker) — this app is mouse-driven and the ring is noise.
        .focusEffectDisabled()
    }

    private func validateMinimumItems() {
        if !settings.hasAtLeastOneItem {
            settings.ensureAtLeastOneItem()
            showMinimumItemAlert = true
        }
    }
}

// MARK: - Settings Grid Item

struct SettingsGridItem: View {
    enum DemoLevel {
        case low, medium, high

        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .yellow
            case .high: return .red
            }
        }

        var label: String {
            switch self {
            case .low: return "health.level.low".localized
            case .medium: return "health.level.medium".localized
            case .high: return "health.level.high".localized
            }
        }
    }

    let title: String
    @Binding var isOn: Bool
    let icon: String
    /// When set, renders this template asset instead of the `icon` SF Symbol.
    var assetIcon: String?
    let onChange: () -> Void

    var body: some View {
        Button {
            isOn.toggle()
            onChange()
        } label: {
            VStack(spacing: 5) {
                iconView
                    .foregroundColor(isOn ? .blue : .secondary)

                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isOn ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? Color.blue.opacity(0.1) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? Color.blue.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var iconView: some View {
        if let assetIcon {
            Image(assetIcon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
        } else {
            Image(systemName: icon)
                .font(.system(size: 15))
        }
    }
}

// MARK: - Health Dimension Button

/// 健康分维度按钮：纯文字，无图标，点击切换开关。
private struct HealthDimButton: View {
    let title: String
    @Binding var isOn: Bool
    let demoLevel: SettingsGridItem.DemoLevel
    let useColorIndicator: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(demoLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
                )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var demoLabel: String {
        if useColorIndicator {
            return title
        } else {
            return "\(title) \(demoLevel.label)"
        }
    }

    private var textColor: Color {
        guard isOn else { return .secondary }
        return useColorIndicator ? demoLevel.color : .primary
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
