//
//  SettingsView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//
//  List-detail 设置面板：左侧 SettingsCategory 侧栏，右侧按选中分类切换的详情面板。
//  用普通 HStack 而非 NavigationSplitView——后者在 `Settings { }` scene 里有尺寸 /
//  侧栏折叠 / 焦点环传播的坑（详见方案评审）。选中项用 @AppStorage 持久化，使
//  `.id(language)` 重建语言时不丢选中、不出现空白详情。
//

import SwiftUI

// MARK: - Category

/// 设置分类。三组分区对应「通用 / 监控（核心）/ 附加工具（默认关闭）」，保留旧版的
/// opt-in 分组语义，让用户一眼看出哪些是可选的越界能力。
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, menuBar, health
    case scroll, windowManagement, finderMenu, aiUsage, network

    var id: String { rawValue }

    enum Group { case general, monitoring, extras }

    var group: Group {
        switch self {
        case .general: return .general
        case .menuBar, .health: return .monitoring
        case .scroll, .windowManagement, .finderMenu, .aiUsage, .network: return .extras
        }
    }

    /// 侧栏标题的本地化 key（尽量复用旧卡片标题，减少新增键）。
    var titleKey: String {
        switch self {
        case .general: return "settings.general"
        case .menuBar: return "settings.statusBar"
        case .health: return "settings.health"
        case .scroll: return "settings.inputDevices"
        case .windowManagement: return "settings.windowManagement"
        case .finderMenu: return "settings.finderMenu"
        case .aiUsage: return "settings.aiUsage"
        case .network: return "settings.exitNode.section"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .health: return "heart.text.square"
        case .scroll: return "arrow.up.arrow.down"
        case .windowManagement: return "macwindow"
        case .finderMenu: return "filemenu.and.cursorarrow"
        case .aiUsage: return "sparkles"
        case .network: return "network"
        }
    }

    static func items(in group: Group) -> [SettingsCategory] {
        allCases.filter { $0.group == group }
    }

    /// 该 opt-in 工具当前是否处于启用状态——用于侧栏的绿色「live」信号点。
    /// 监控核心（general/menuBar/health）永远返回 false：它们不是可开关的越界能力。
    func isActive(_ settings: SettingsManager) -> Bool {
        switch self {
        case .scroll:
            return settings.scrollReverseEnabled || settings.scrollReverseHorizontalEnabled
        case .windowManagement:
            return settings.windowManagementEnabled
        case .finderMenu:
            return settings.finderMenuEnabled
        case .aiUsage:
            return settings.aiMonitorClaudeEnabled || settings.aiMonitorCodexEnabled || settings.aiMonitorGeminiEnabled
        case .network:
            return settings.exitNodeDetectionEnabled
        case .general, .menuBar, .health:
            return false
        }
    }
}

// MARK: - Root

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @AppStorage("settings.selectedCategory") private var selectedRaw = SettingsCategory.general.rawValue
    @State private var showMinimumItemAlert = false
    @State private var showExitPrivacyAlert = false

    private var selectedCategory: SettingsCategory {
        SettingsCategory(rawValue: selectedRaw) ?? .general
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // 固定尺寸：Settings 窗口会记忆上次 frame，用 min/ideal 会被记忆值盖过导致窗口
        // 失控变大。固定宽高由内容驱动窗口尺寸（沿用旧版做法），稳定可预期。
        .frame(width: 480, height: 620)
        .background(
            GlassBackgroundView(cornerRadius: 0, fallbackMaterial: .underWindowBackground, configuresWindow: true)
                .ignoresSafeArea()
        )
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
        .focusable(false)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: Binding<SettingsCategory?>(
            get: { selectedCategory },
            set: { if let value = $0 { selectedRaw = value.rawValue } }
        )) {
            sidebarSection(.general, header: "settings.section.general")
            sidebarSection(.monitoring, header: "settings.section.monitoring")
            sidebarSection(.extras, header: "settings.section.extras")
        }
        .listStyle(.sidebar)
        .frame(width: 160)
        .focusable(false)
    }

    @ViewBuilder
    private func sidebarSection(_ group: SettingsCategory.Group, header: String) -> some View {
        Section {
            ForEach(SettingsCategory.items(in: group)) { category in
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .font(.system(size: 13))
                        .frame(width: 18)
                    Text(category.titleKey.localized)
                        .font(.system(size: 12))
                    Spacer(minLength: 4)
                    // 绿色 live 信号点：仅当该 opt-in 工具正在运行时出现，一眼看清哪些
                    // 越界能力被打开了（呼应「opt-in by construction」的产品原则）。
                    if category.isActive(settings) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }
                .tag(category)
            }
        } header: {
            Text(header.localized)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedCategory {
        case .general:
            GeneralDetail(settings: settings, updateManager: updateManager)
        case .menuBar:
            MenuBarDetail(settings: settings, onValidate: validateMinimumItems)
        case .health:
            HealthDetail(settings: settings)
        case .scroll:
            ScrollDetail(settings: settings)
        case .windowManagement:
            WindowManagementDetail(settings: settings)
        case .finderMenu:
            FinderMenuDetail(settings: settings, openSettings: openLoginItemsAndExtensionsSettings)
        case .aiUsage:
            AIUsageDetail(settings: settings)
        case .network:
            NetworkDetail(settings: settings, showPrivacyAlert: $showExitPrivacyAlert)
        }
    }

    // MARK: Helpers

    private func validateMinimumItems() {
        if !settings.hasAtLeastOneItem {
            settings.ensureAtLeastOneItem()
            showMinimumItemAlert = true
        }
    }

    /// 打开「系统设置 › 登录项与扩展」，引导用户启用 Finder 扩展。沙盒 App 不能用
    /// pluginkit 自注册，启用只能由用户手动完成。
    private func openLoginItemsAndExtensionsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Detail scaffold

/// 详情面板骨架：标题（可带右侧开关等附件）+ 内容，统一内边距。取代旧的 BentoCard，
/// 用留白与发丝分隔线表达层级，而非嵌套卡片。
struct SettingsDetailScaffold<Accessory: View, Content: View>: View {
    private let title: String
    private let accessory: Accessory
    private let content: Content

    init(_ title: String,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
                accessory
            }
            .padding(.bottom, 12)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// 分组容器：把相关行收进一个下沉、发丝边框的圆角面板（macOS / Linear 设置组的样子），
/// 用留白与分隔线表达层级，而非嵌套卡片。行之间的 `Divider` 由调用方插入。
struct SettingsGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
    }
}

/// 一行设置：左标签 + 右控件，统一内边距，置于 SettingsGroup 内。
struct SettingsRow<Control: View>: View {
    private let title: String
    private let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
struct HealthDimButton: View {
    let title: String
    @Binding var isOn: Bool
    let demoLevel: SettingsGridItem.DemoLevel
    let useColorIndicator: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isOn ? .primary : .secondary)
                Text(demoLevel.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(levelColor)
            }
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

    /// 等级词的颜色：关闭时统一灰；开启时按偏好——颜色模式用红/黄/绿，文字模式保持中性。
    private var levelColor: Color {
        guard isOn else { return .secondary }
        return useColorIndicator ? demoLevel.color : .secondary
    }
}

// MARK: - Settings Toggle

/// Reusable switch component — styling only; focus suppression is handled
/// globally via `.focusable(false)` on the root.
struct SettingsToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
