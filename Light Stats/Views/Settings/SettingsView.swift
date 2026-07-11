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

/// 设置分类。侧栏只负责导航，不承载功能运行状态。
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, monitoring, extras

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .general: return "settings.general"
        case .monitoring: return "settings.section.monitoring"
        case .extras: return "settings.section.extras"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .monitoring: return "waveform.path.ecg"
        case .extras: return "switch.2"
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
            // 详情面板包一层垂直 ScrollView：内容超过固定窗高（如 Finder 文件模板有
            // 一二十行）时可滚动，短页面照常顶部对齐不受影响。
            ScrollView(.vertical) {
                detail
                    .frame(width: 560, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        // 固定尺寸：Settings 窗口会记忆上次 frame，用 min/ideal 会被记忆值盖过导致窗口
        // 失控变大。固定宽高由内容驱动窗口尺寸（沿用旧版做法），稳定可预期。
        .frame(width: 900, height: 640)
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
            ForEach(SettingsCategory.allCases) { category in
                sidebarRow(category)
                    .tag(category)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 190)
        .focusable(false)
    }

    private func sidebarRow(_ category: SettingsCategory) -> some View {
        HStack(spacing: 9) {
            Image(systemName: category.icon)
                .font(.system(size: 14))
                .frame(width: 19)
            Text(category.titleKey.localized)
                .font(.system(size: 13))
        }
        .frame(minHeight: 28)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedCategory {
        case .general:
            GeneralDetail(
                settings: settings,
                updateManager: updateManager,
                openDiagnosticLogs: openDiagnosticLogs
            )
        case .monitoring:
            MonitoringDetail(settings: settings, onValidate: validateMinimumItems)
        case .extras:
            ExtrasDetail(
                settings: settings,
                showPrivacyAlert: $showExitPrivacyAlert,
                openSettings: openLoginItemsAndExtensionsSettings
            )
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

    private func openDiagnosticLogs() {
        Task {
            await DiagnosticLogService.shared.flush()
            NSWorkspace.shared.open(DiagnosticLogService.diagnosticsDirectoryURL)
        }
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
                Text(title).font(.system(size: 22, weight: .semibold))
                Spacer()
                accessory
            }
            .padding(.bottom, 24)
            VStack(alignment: .leading, spacing: 22) {
                content
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// 页面内的语义分组：标题在容器外，相关设置行收进同一个连续面板。
struct SettingsSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content
        }
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.09)))
    }
}

/// 一行设置：左标签 + 右控件，统一内边距，置于 SettingsGroup 内。
struct SettingsRow<Control: View>: View {
    private let title: String
    private let subtitle: String?
    private let control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, subtitle == nil ? 8 : 7)
        .frame(minHeight: 40)
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
