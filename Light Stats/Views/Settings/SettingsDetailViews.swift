//
//  SettingsDetailViews.swift
//  Light Stats
//
//  设置面板各分类的详情视图。每个 detail 复用既有控件（SettingsToggle / SettingsGridItem /
//  HealthDimButton / Picker / Slider），用 SettingsDetailScaffold + SettingsGroup 取代
//  BentoCard——分组下沉面板 + 发丝分隔线表达层级。与 SettingsView.swift 拆分以控制单文件长度。
//

import SwiftUI

/// 组内行间分隔线，左侧内缩对齐标签。
private func rowDivider() -> some View {
    Divider().padding(.leading, 12)
}

// MARK: - General

struct GeneralDetail: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var updateManager: UpdateManager
    let openDiagnosticLogs: () -> Void

    var body: some View {
        SettingsDetailScaffold("settings.general".localized) {
            SettingsSection("settings.general.app".localized) {
                SettingsGroup {
                    SettingsRow("settings.launchAtLogin".localized) {
                        SettingsToggle(isOn: $settings.launchAtLogin)
                    }
                    rowDivider()
                    SettingsRow(
                        "settings.keepAwake".localized,
                        subtitle: "settings.keepAwake.description".localized
                    ) {
                        SettingsToggle(isOn: $settings.keepAwakeEnabled)
                    }
                    rowDivider()
                    SettingsRow("settings.language".localized) {
                        Picker("", selection: $settings.appLanguage) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.shortName).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize().focusable(false)
                    }
                    rowDivider()
                    SettingsRow(
                        "settings.appLogs".localized,
                        subtitle: "settings.appLogs.hint".localized
                    ) {
                        Button("settings.view".localized, action: openDiagnosticLogs)
                            .controlSize(.small)
                    }
                }
            }
            SettingsSection("settings.update.section".localized) {
                SettingsGroup {
                    updateRow
                }
            }
        }
    }

    private var updateRow: some View {
        HStack(spacing: 10) {
            Button {
                updateManager.check(userInitiated: true)
            } label: {
                HStack(spacing: 5) {
                    if updateManager.isChecking {
                        ProgressView().controlSize(.small).scaleEffect(0.8)
                    }
                    Text((updateManager.isChecking ? "update.checking" : "settings.update.manualCheck").localized)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .disabled(updateManager.isChecking)

            Spacer()

            if let release = updateManager.availableRelease {
                Button("settings.update.installVersion".localized(release.tagName)) {
                    updateManager.presentAvailableRelease()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text("settings.update.automaticLabel".localized)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            SettingsToggle(isOn: $settings.autoCheckUpdates)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
    }
}

// MARK: - Monitoring

struct MonitoringDetail: View {
    @ObservedObject var settings: SettingsManager
    let onValidate: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        SettingsDetailScaffold("settings.section.monitoring".localized) {
            SettingsSection("settings.statusBar".localized) {
                LazyVGrid(columns: columns, spacing: 8) {
                    item("settings.logo", $settings.showLogo, "applelogo", asset: "StatusIcon")
                    item("settings.cpu", $settings.showCPU, "cpu")
                    item("settings.gpu", $settings.showGPU, "square.grid.2x2")
                    item("settings.memory", $settings.showMemory, "memorychip")
                    item("settings.disk", $settings.showDisk, "internaldrive")
                    item("settings.network", $settings.showNetwork, "network")
                    item("settings.fan", $settings.showFan, "fanblades")
                    item("settings.battery", $settings.showBattery, "battery.100")
                    item("settings.health", $settings.showHealth, "heart.text.square")
                }
            }
            SettingsSection("settings.refreshAndUnits".localized) {
                SettingsGroup {
                    SettingsRow("settings.refreshRate.label".localized) {
                        Picker("", selection: $settings.refreshRate) {
                            ForEach(SettingsManager.RefreshRate.allCases, id: \.self) { rate in
                                Text(rate.displayName).tag(rate)
                            }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize().focusable(false)
                    }
                    rowDivider()
                    SettingsRow("settings.temperatureUnit".localized) {
                        Picker("", selection: $settings.temperatureUnit) {
                            ForEach(SettingsManager.TemperatureUnit.allCases, id: \.self) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented).labelsHidden().focusable(false)
                    }
                }
            }
            SettingsSection("settings.appearance".localized) {
                SettingsGroup {
                    SettingsRow(
                        "settings.flatColors.section".localized,
                        subtitle: "settings.flatColors.hint".localized
                    ) {
                        SettingsToggle(isOn: $settings.useFlatColors)
                    }
                    rowDivider()
                    SettingsRow(
                        "settings.colorIndicator".localized,
                        subtitle: "settings.accessibility.colorIndicator.hint".localized
                    ) {
                        SettingsToggle(isOn: $settings.useColorIndicator)
                    }
                }
            }
            SettingsSection("settings.health".localized) {
                LazyVGrid(columns: columns, spacing: 8) {
                    dim("health.dimension.cpu", $settings.healthIncludeCPU, .low)
                    dim("health.dimension.memory", $settings.healthIncludeMemory, .low)
                    dim("health.dimension.load", $settings.healthIncludeLoad, .medium)
                    dim("health.dimension.temperature", $settings.healthIncludeTemperature, .high)
                    dim("health.dimension.gpu", $settings.healthIncludeGPU, .medium)
                    dim("settings.healthDimensions.power", $settings.healthIncludePower, .low)
                }
                Text("settings.healthDimensions.hint".localized)
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func item(_ key: String, _ isOn: Binding<Bool>, _ icon: String, asset: String? = nil) -> some View {
        SettingsGridItem(title: key.localized, isOn: isOn, icon: icon, assetIcon: asset, onChange: onValidate)
    }

    private func dim(_ key: String, _ isOn: Binding<Bool>, _ level: SettingsGridItem.DemoLevel) -> some View {
        HealthDimButton(
            title: key.localized, isOn: isOn,
            demoLevel: level, useColorIndicator: settings.useColorIndicator
        )
    }
}

// MARK: - Extras

struct ExtrasDetail: View {
    @ObservedObject var settings: SettingsManager
    @Binding var showPrivacyAlert: Bool
    let openSettings: () -> Void

    var body: some View {
        SettingsDetailScaffold("settings.section.extras".localized) {
            ScrollDetail(settings: settings)
            WindowManagementDetail(settings: settings)
            AIUsageDetail(settings: settings)
            NetworkDetail(settings: settings, showPrivacyAlert: $showPrivacyAlert)
            FinderMenuDetail(settings: settings, openSettings: openSettings)
        }
    }
}

// MARK: - Scroll

struct ScrollDetail: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        SettingsSection("settings.inputDevices".localized) {
            SettingsGroup {
                SettingsRow("settings.scrollReverse".localized) {
                    SettingsToggle(isOn: $settings.scrollReverseEnabled)
                }
                rowDivider()
                SettingsRow("settings.scrollReverseHorizontal".localized) {
                    SettingsToggle(isOn: $settings.scrollReverseHorizontalEnabled)
                }
                rowDivider()
                stepRow
            }
        }
    }

    /// 步长倍率滑块。两个反转都关闭时禁用并淡化，提示当前不生效。
    private var stepRow: some View {
        let active = settings.scrollReverseEnabled || settings.scrollReverseHorizontalEnabled
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("settings.scrollStep".localized)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.2f×", settings.scrollStepMultiplier))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Slider(value: $settings.scrollStepMultiplier, in: 0.25...3.0, step: 0.05)
                .controlSize(.small).focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(!active).opacity(active ? 1 : 0.45)
    }
}

// MARK: - Window Management

struct WindowManagementDetail: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        SettingsSection("settings.windowManagement".localized) {
            SettingsGroup {
                SettingsRow(
                    "settings.windowManagement".localized,
                    subtitle: "settings.windowManagement.description".localized
                ) {
                    SettingsToggle(isOn: $settings.windowManagementEnabled)
                }
            }
        }
    }
}

// MARK: - AI Usage

struct AIUsageDetail: View {
    @ObservedObject var settings: SettingsManager

    private var anyEnabled: Bool {
        settings.aiMonitorClaudeEnabled || settings.aiMonitorCodexEnabled || settings.aiMonitorGeminiEnabled
    }

    var body: some View {
        SettingsSection("settings.aiUsage".localized) {
            SettingsGroup {
                SettingsRow("aiUsage.claude".localized) {
                    SettingsToggle(isOn: $settings.aiMonitorClaudeEnabled)
                }
                if settings.aiMonitorClaudeEnabled {
                    rowDivider()
                    SettingsRow("aiUsage.autoRefresh".localized) {
                        SettingsToggle(isOn: $settings.autoRefreshClaudeEnabled)
                    }
                }
                rowDivider()
                SettingsRow("aiUsage.codex".localized) {
                    SettingsToggle(isOn: $settings.aiMonitorCodexEnabled)
                }
                if settings.aiMonitorCodexEnabled {
                    rowDivider()
                    SettingsRow("aiUsage.autoRefresh".localized) {
                        SettingsToggle(isOn: $settings.autoRefreshCodexEnabled)
                    }
                }
                rowDivider()
                SettingsRow("aiUsage.gemini".localized) {
                    SettingsToggle(isOn: $settings.aiMonitorGeminiEnabled)
                }
                if anyEnabled {
                    rowDivider()
                    SettingsRow("settings.aiUsageInterval".localized) {
                        Text(SettingsManager.AIRefreshInterval.m2.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Network (exit node)

struct NetworkDetail: View {
    @ObservedObject var settings: SettingsManager
    @Binding var showPrivacyAlert: Bool

    var body: some View {
        SettingsSection("settings.exitNode.section".localized) {
            SettingsGroup {
                SettingsRow(
                    "settings.exitNode.toggle".localized,
                    subtitle: "settings.exitNode.toggleHint".localized
                ) {
                    SettingsToggle(isOn: Binding(
                        get: { settings.exitNodeDetectionEnabled },
                        set: { newValue in
                            if newValue {
                                showPrivacyAlert = true
                            } else {
                                settings.exitNodeDetectionEnabled = false
                            }
                        }
                    ))
                }
                if settings.exitNodeDetectionEnabled {
                    rowDivider()
                    SettingsRow("settings.exitNode.provider".localized) {
                        Picker("", selection: $settings.exitNodeProvider) {
                            ForEach(ExitNodeProvider.allCases, id: \.self) { provider in
                                Text(provider.shortName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize().focusable(false)
                    }
                }
            }
        }
    }
}

// MARK: - Finder Menu (the list-detail editor)

struct FinderMenuDetail: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject private var store = FinderMenuConfigStore.shared
    let openSettings: () -> Void

    /// 哪些文件类型分类当前展开（默认全部收起，保持页面简短）。
    @State private var expandedCategories: Set<FinderMenuPresets.TemplateCategory> = []

    var body: some View {
        SettingsSection("settings.finderMenu".localized) {
            SettingsGroup {
                SettingsRow(
                    "settings.finderMenu".localized,
                    subtitle: "settings.finderMenu.description".localized
                ) {
                    SettingsToggle(isOn: $settings.finderMenuEnabled)
                }
                if settings.finderMenuEnabled {
                    rowDivider()
                    SettingsRow("settings.finderMenu.defaultTerminal".localized) {
                        Picker("", selection: Binding(
                            get: { store.config.terminalID },
                            set: { store.setTerminalID($0) }
                        )) {
                            ForEach(FinderMenuPresets.terminalPresets) { terminal in
                                Text(terminal.name).tag(terminal.id)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().frame(width: 150).focusable(false)
                    }
                    rowDivider()
                    SettingsRow("settings.finderMenu.cmuxActions".localized) {
                        SettingsToggle(isOn: Binding(
                            get: { store.config.showCmuxActions },
                            set: { store.setShowCmuxActions($0) }
                        ))
                    }
                }
            }
            if settings.finderMenuEnabled {
                EditableListView(
                    title: "settings.finderMenu.directories".localized,
                    rows: store.config.favoriteDirectories.map {
                        EditableListRow(id: $0.path, title: $0.name, subtitle: $0.path)
                    },
                    emptyHint: "settings.finderMenu.usingDefaults".localized,
                    onAdd: { store.addDirectory() },
                    onRemove: { id in
                        if let dir = store.config.favoriteDirectories.first(where: { $0.path == id }) {
                            store.removeDirectory(dir)
                        }
                    }
                )
                EditableListView(
                    title: "settings.finderMenu.apps".localized,
                    rows: store.config.openWithApps.map {
                        EditableListRow(id: $0.bundleID, title: $0.name, subtitle: $0.bundleID)
                    },
                    emptyHint: "settings.finderMenu.usingDefaults".localized,
                    onAdd: { store.addApp() },
                    onRemove: { id in
                        if let app = store.config.openWithApps.first(where: { $0.bundleID == id }) {
                            store.removeApp(app)
                        }
                    }
                )
                templateChooser
                extensionStatusRow
                HStack(spacing: 8) {
                    Button("settings.finderMenu.openSettings".localized) { openSettings() }
                    Button("settings.finderMenu.refreshFinder".localized) { store.restartFinder() }
                }
                .font(.system(size: 11))
            }
        }
        .onAppear { store.refreshExtensionStatus() }
    }

    /// 显示扩展在系统层的真实启用状态——app 总开关之外的第二道门（系统设置里的勾）。
    @ViewBuilder private var extensionStatusRow: some View {
        let (symbol, color, key): (String, Color, String) = {
            switch store.extensionStatus {
            case .enabled:
                return ("checkmark.circle.fill", .green, "settings.finderMenu.status.enabled")
            case .disabled:
                return ("exclamationmark.triangle.fill", .orange, "settings.finderMenu.status.disabled")
            case .notRegistered:
                return ("exclamationmark.triangle.fill", .orange, "settings.finderMenu.status.notRegistered")
            case .unknown:
                return ("questionmark.circle", .secondary, "settings.finderMenu.status.unknown")
            }
        }()
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundColor(color)
            Text(key.localized)
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「新建文件」类型选择器：按分类分组、可折叠；每个类型一个开关，勾选即显示在右键子菜单。
    private var templateChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.finderMenu.templates".localized)
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            Text("settings.finderMenu.templatesHint".localized)
                .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(FinderMenuPresets.TemplateCategory.allCases, id: \.self) { category in
                templateCategorySection(category)
            }
        }
    }

    private func templateCategorySection(_ category: FinderMenuPresets.TemplateCategory) -> some View {
        let items = FinderMenuPresets.fileTemplates(in: category)
        let enabledCount = items.filter { store.isPresetTemplateEnabled($0.id) }.count
        let isExpanded = expandedCategories.contains(category)
        return VStack(spacing: 0) {
            Button {
                if isExpanded { expandedCategories.remove(category) } else { expandedCategories.insert(category) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 10)
                    Text(category.titleKey.localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(enabledCount)/\(items.count)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(enabledCount > 0 ? .secondary : .secondary.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                SettingsGroup {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, template in
                        if index > 0 { rowDivider() }
                        SettingsRow(template.title) {
                            SettingsToggle(isOn: Binding(
                                get: { store.isPresetTemplateEnabled(template.id) },
                                set: { store.setPresetTemplate(template.id, enabled: $0) }
                            ))
                        }
                    }
                }
                .padding(.leading, 16)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06)))
    }
}

// MARK: - Editable List (custom +/- editor)

/// 一行可编辑列表项。
private struct EditableListRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

/// 原生 macOS 风格的 +/- 列表编辑器：定高发丝边框区域（内部滚动）+ 底部 + / − 栏。
/// 刻意不用 SwiftUI List（避免嵌套滚动与焦点环传播问题，见方案评审）。行支持悬停与选中高亮。
private struct EditableListView: View {
    let title: String
    let rows: [EditableListRow]
    let emptyHint: String
    let onAdd: () -> Void
    let onRemove: (String) -> Void

    @State private var selection: String?
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            VStack(spacing: 0) {
                rowsRegion
                Divider()
                footer
            }
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.025)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.1)))
        }
    }

    @ViewBuilder
    private var rowsRegion: some View {
        if rows.isEmpty {
            Text(emptyHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .padding(.horizontal, 10)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                        if row.id != rows.last?.id {
                            Divider().padding(.leading, 10)
                        }
                    }
                }
            }
            .frame(height: 118)
        }
    }

    private func rowView(_ row: EditableListRow) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 11, weight: .medium))
                Text(row.subtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(row.id))
        .contentShape(Rectangle())
        .onTapGesture { selection = row.id }
        .onHover { hovered = $0 ? row.id : (hovered == row.id ? nil : hovered) }
    }

    private func rowBackground(_ id: String) -> Color {
        if selection == id { return Color.accentColor.opacity(0.18) }
        if hovered == id { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var footer: some View {
        HStack(spacing: 2) {
            gutterButton("plus", enabled: true) { onAdd() }
            gutterButton("minus", enabled: selection != nil) {
                if let selection { onRemove(selection) }
                selection = nil
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func gutterButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 22, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .secondary : .quaternary)
        .disabled(!enabled)
    }
}
