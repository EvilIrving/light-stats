//
//  SettingsDetailViews.swift
//  Light Stats
//
//  设置面板各分类的详情视图。每个 detail 复用既有控件（SettingsToggle / SettingsGridItem /
//  HealthDimButton / Picker / Slider），用 SettingsDetailScaffold + SettingsGroup 取代
//  SettingsGroup + 发丝分隔线表达层级。与 SettingsView.swift 拆分以控制单文件长度。
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
            SettingsSection("settings.theme".localized) {
                VStack(alignment: .leading, spacing: 10) {
                    ThemePickerView(selection: $settings.appTheme)
                    themeAppearanceControls
                }
            }
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
                        SettingsSegmentedPicker(selection: $settings.appLanguage, segmentMinWidth: 40) {
                            ForEach(AppLanguage.allCases) { lang in
                                SettingsSegmentLabel(title: lang.shortName).tag(lang)
                            }
                        }
                    }
                    rowDivider()
                    SettingsRow(
                        "settings.appLogs".localized,
                        subtitle: "settings.appLogs.hint".localized
                    ) {
                        HStack(spacing: 8) {
                            SettingsSegmentedPicker(
                                selection: $settings.diagnosticLogLevel,
                                segmentMinWidth: 52
                            ) {
                                ForEach(SettingsManager.DiagnosticLogLevel.allCases, id: \.self) { level in
                                    SettingsSegmentLabel(title: level.displayName).tag(level)
                                }
                            }
                            Button("settings.view".localized, action: openDiagnosticLogs)
                                .controlSize(.regular)
                        }
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

    func meshAppearanceControls(
        tokens: ThemeTokens,
        grainEnabled: Binding<Bool>,
        lightFlow: Binding<Double>,
        lightPositionX: Binding<Double>,
        lightPositionY: Binding<Double>,
        presets: ThemeAppearancePresetConfiguration
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            meshLivePreview(tokens: tokens)
            SettingsGroup {
                SettingsRow(
                    "settings.theme.film.grain".localized,
                    subtitle: "settings.theme.film.grain.hint".localized
                ) {
                    SettingsToggle(isOn: grainEnabled)
                }
                rowDivider()
                filmSegmentedRow(
                    title: "settings.theme.film.lightFlow".localized,
                    value: lightFlow,
                    options: presets.flowValues,
                    format: FilmAppearanceLabel.flow
                )
                rowDivider()
                filmSegmentedRow(
                    title: "settings.theme.film.lightPositionX".localized,
                    value: lightPositionX,
                    options: presets.positionValues,
                    format: FilmAppearanceLabel.horizontalPosition
                )
                rowDivider()
                filmSegmentedRow(
                    title: "settings.theme.film.lightPositionY".localized,
                    value: lightPositionY,
                    options: presets.positionValues,
                    format: FilmAppearanceLabel.verticalPosition
                )
            }
        }
    }
    private func meshLivePreview(tokens: ThemeTokens) -> some View {
        ThemeBackgroundView(
            tokens: tokens,
            appearance: settings.themeAppearance(for: tokens.theme),
            cornerRadius: 10
        )
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .accessibilityLabel(tokens.theme.titleKey.localized)
    }

    private func filmSegmentedRow(
        title: String,
        value: Binding<Double>,
        options: [Double],
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary)
            Picker("", selection: FilmAppearanceLabel.discreteBinding(value, options: options)) {
                ForEach(options, id: \.self) { option in
                    Text(format(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
                .focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// 单行：检查按钮 + 可用版本入口 + 稳定/Beta 通道 + 自动更新开关。
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

            SettingsSegmentedPicker(selection: $settings.includeBetaUpdates, segmentMinWidth: 48) {
                SettingsSegmentLabel(title: "settings.update.channel.stable".localized).tag(false)
                SettingsSegmentLabel(title: "settings.update.channel.beta".localized).tag(true)
            }
            .help("settings.update.channel.hint".localized)

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
                        SettingsSegmentedPicker(selection: $settings.refreshRate, segmentMinWidth: 56) {
                            ForEach(SettingsManager.RefreshRate.allCases, id: \.self) { rate in
                                SettingsSegmentLabel(title: rate.displayName).tag(rate)
                            }
                        }
                    }
                    rowDivider()
                    SettingsRow("settings.temperatureUnit".localized) {
                        SettingsSegmentedPicker(selection: $settings.temperatureUnit, segmentMinWidth: 48) {
                            ForEach(SettingsManager.TemperatureUnit.allCases, id: \.self) { unit in
                                SettingsSegmentLabel(title: unit.displayName).tag(unit)
                            }
                        }
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
                    .font(.system(size: 10)).foregroundStyle(Color.secondary)
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
                        SettingsSegmentedPicker(selection: $settings.exitNodeProvider, segmentMinWidth: 52) {
                            ForEach(ExitNodeProvider.allCases, id: \.self) { provider in
                                SettingsSegmentLabel(title: provider.shortName).tag(provider)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Finder Menu (the list-detail editor)

struct FinderMenuDetail: View {
    @Environment(\.theme) private var theme
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
                extensionFooter
            }
        }
        .onAppear { store.refreshExtensionStatus() }
    }

    /// 扩展状态 + 情境化动作。已启用时只提示成功，并保留轻量「刷新访达」；
    /// 未启用 / 未注册时才露出「在系统设置中启用」主按钮，避免已就绪时还推用户去设置。
    @ViewBuilder private var extensionFooter: some View {
        let isReady = store.extensionStatus == .enabled
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                Text(statusMessageKey.localized)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if isReady {
                    Button("settings.finderMenu.refreshFinder".localized) {
                        store.restartFinder()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkSecondary)
                    .controlSize(.small)
                }
            }

            if !isReady {
                HStack(spacing: 8) {
                    Button("settings.finderMenu.openSettings".localized) { openSettings() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("settings.finderMenu.refreshFinder".localized) {
                        store.restartFinder()
                        store.refreshExtensionStatus()
                    }
                    .controlSize(.small)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isReady ? theme.signalGood.opacity(0.12) : theme.signalWarn.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isReady ? theme.signalGood.opacity(0.28) : theme.signalWarn.opacity(0.28))
        )
    }

    private var statusSymbol: String {
        switch store.extensionStatus {
        case .enabled: return "checkmark.circle.fill"
        case .disabled, .notRegistered: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch store.extensionStatus {
        case .enabled: return theme.signalGood
        case .disabled, .notRegistered: return theme.signalWarn
        case .unknown: return theme.inkSecondary
        }
    }

    private var statusMessageKey: String {
        switch store.extensionStatus {
        case .enabled: return "settings.finderMenu.status.enabled"
        case .disabled: return "settings.finderMenu.status.disabled"
        case .notRegistered: return "settings.finderMenu.status.notRegistered"
        case .unknown: return "settings.finderMenu.status.unknown"
        }
    }

    /// 「新建文件」类型选择器：单层 SettingsGroup，分类头与类型开关同级，可折叠但不嵌套卡片。
    private var templateChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.finderMenu.templates".localized)
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            Text("settings.finderMenu.templatesHint".localized)
                .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            SettingsGroup {
                let categories = FinderMenuPresets.TemplateCategory.allCases
                ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                    if index > 0 { rowDivider() }
                    templateCategoryHeader(category)
                    if expandedCategories.contains(category) {
                        ForEach(FinderMenuPresets.fileTemplates(in: category), id: \.id) { template in
                            rowDivider()
                            SettingsRow(template.title) {
                                SettingsToggle(isOn: Binding(
                                    get: { store.isPresetTemplateEnabled(template.id) },
                                    set: { store.setPresetTemplate(template.id, enabled: $0) }
                                ))
                            }
                        }
                    }
                }
            }
        }
    }

    /// 分类头：与类型行同级，点击展开/收起下属开关，无第二层卡片。
    private func templateCategoryHeader(_ category: FinderMenuPresets.TemplateCategory) -> some View {
        let items = FinderMenuPresets.fileTemplates(in: category)
        let enabledCount = items.filter { store.isPresetTemplateEnabled($0.id) }.count
        let isExpanded = expandedCategories.contains(category)
        return Button {
            if isExpanded {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Text(category.titleKey.localized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 8)
                Text("\(enabledCount)/\(items.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(enabledCount > 0 ? .secondary : .secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @Environment(\.theme) private var theme

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
                .foregroundStyle(theme.inkFaint)
            VStack(spacing: 0) {
                rowsRegion
                Divider()
                footer
            }
            // 与 SettingsGroup 同表面策略：glass 用系统控件底，其它主题用 cardFill。
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.usesGlass ? Color(nsColor: .controlBackgroundColor) : theme.surfaceFill)
                    .shadow(color: Color.black.opacity(theme.surfaceShadowOpacity * 0.7), radius: 1.5, y: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(theme.surfaceStroke)
            )
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

    /// 单行：名称 + 间距 + 副标题（路径 / bundle id），小字副标题居中截断。
    private func rowView(_ row: EditableListRow) -> some View {
        HStack(spacing: 10) {
            Text(row.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .layoutPriority(1)
            Text(row.subtitle)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
