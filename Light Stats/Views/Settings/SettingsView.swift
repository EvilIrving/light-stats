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

    /// Shared white canvas for sidebar + detail. Settings never follows `appTheme`.
    private var settingsCanvas: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            // 发丝分隔，比系统 Divider 更轻，贴近两侧同色画布。
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)
                .ignoresSafeArea()
            // 详情面板包一层垂直 ScrollView：内容超过固定窗高（如 Finder 文件模板有
            // 一二十行）时可滚动，短页面照常顶部对齐不受影响。
            ScrollView(.vertical) {
                detail
                    // 详情区加宽：左侧标签 + 副文案更不易折行，右侧分段控件也有呼吸感。
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(settingsCanvas)
        }
        // 固定尺寸：Settings 窗口会记忆上次 frame，用 min/ideal 会被记忆值盖过导致窗口
        // 失控变大。固定宽高由内容驱动窗口尺寸（沿用旧版做法），稳定可预期。
        .frame(width: 980, height: 640)
        .background(settingsCanvas.ignoresSafeArea())
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
        // Lock chrome to bento; do not pass `settings.appTheme`.
        .appThemed(.bento)
        .focusable(false)
    }

    // MARK: Sidebar

    /// 自绘浅色侧栏：与详情同画布，选中项用圆角浅色高亮，不再用系统深灰 `.sidebar` 样式。
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SettingsCategory.allCases) { category in
                Button {
                    selectedRaw = category.rawValue
                } label: {
                    sidebarRow(category, isSelected: selectedCategory == category)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 190, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(settingsCanvas)
        .focusable(false)
    }

    private func sidebarRow(_ category: SettingsCategory, isSelected: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: category.icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            Text(category.titleKey.localized)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.82))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedCategory {
        case .general:
            GeneralDetail(
                settings: settings,
                updateManager: updateManager,
                openDiagnosticLogs: settings.openDiagnosticLogs
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

}

// MARK: - Detail scaffold

/// 详情面板骨架：标题（可带右侧开关等附件）+ 内容，统一内边距。取代旧的 BentoCard，
/// 用留白与发丝分隔线表达层级，而非嵌套卡片。
struct SettingsDetailScaffold<Accessory: View, Content: View>: View {
    @Environment(\.theme) private var theme
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
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.inkPrimary)
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
    @Environment(\.theme) private var theme
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
                .foregroundStyle(theme.inkPrimary)
            content
        }
    }
}

/// 分组容器：与页面同为白色底，靠发丝描边 + 极轻阴影区分卡片边界。
/// 行之间的 `Divider` 由调用方插入。
struct SettingsGroup<Content: View>: View {
    @Environment(\.theme) private var theme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.usesGlass ? Color(nsColor: .controlBackgroundColor) : theme.surfaceFill)
                .shadow(color: Color.black.opacity(theme.surfaceShadowOpacity * 0.7), radius: 1.5, y: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.surfaceStroke)
        )
    }
}

/// 一行设置：左标签 + 右控件，统一内边距，置于 SettingsGroup 内。
struct SettingsRow<Control: View>: View {
    @Environment(\.theme) private var theme
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
                    .foregroundStyle(theme.inkPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // 文案优先占宽，右侧控件保持 intrinsic 宽度，减少副标题折行。
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            control
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, subtitle == nil ? 8 : 7)
        .frame(minHeight: 40)
    }
}

/// 分段选择器统一样式：各段等宽、固定高度，避免「关 / 仅错误 / 完整」这种长短不一的视觉抖动。
struct SettingsSegmentedPicker<Selection: Hashable, Content: View>: View {
    @Binding var selection: Selection
    /// 单段最小宽度；语言 5 段用窄一些，日志 3 段用宽一些。
    var segmentMinWidth: CGFloat = 48
    @ViewBuilder var content: () -> Content

    var body: some View {
        Picker("", selection: $selection) {
            content()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.regular)
        .fixedSize()
        .focusable(false)
        // 通过环境把 minWidth 传给各段 Text（调用方用 SettingsSegmentLabel）。
        .environment(\.settingsSegmentMinWidth, segmentMinWidth)
    }
}

/// 分段选项标签：等宽居中，保证选中/未选中胶囊视觉一致。
struct SettingsSegmentLabel: View {
    @Environment(\.settingsSegmentMinWidth) private var minWidth
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .frame(minWidth: minWidth, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

private struct SettingsSegmentMinWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 48
}

extension EnvironmentValues {
    var settingsSegmentMinWidth: CGFloat {
        get { self[SettingsSegmentMinWidthKey.self] }
        set { self[SettingsSegmentMinWidthKey.self] = newValue }
    }
}

// MARK: - Settings Grid Item

struct SettingsGridItem: View {
    enum DemoLevel {
        case low, medium, high

        /// Legacy helper — prefer `ThemeTokens` signal colors at call sites.
        var color: Color {
            switch self {
            case .low: return Color(red: 0.20, green: 0.72, blue: 0.38)
            case .medium: return Color(red: 0.92, green: 0.72, blue: 0.12)
            case .high: return Color(red: 0.90, green: 0.28, blue: 0.24)
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

    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            isOn.toggle()
            onChange()
        } label: {
            VStack(spacing: 5) {
                iconView
                    .foregroundStyle(isOn ? theme.accent : theme.inkSecondary)

                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isOn ? theme.inkPrimary : theme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? theme.accent.opacity(0.14) : theme.wellFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? theme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
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
    @Environment(\.theme) private var theme

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
                    .foregroundStyle(isOn ? theme.inkPrimary : theme.inkSecondary)
                Text(demoLevel.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(levelColor)
            }
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? theme.rowHoverFill : theme.wellFill)
            )
        }
        .buttonStyle(.plain)
    }

    /// 等级词的颜色：关闭时统一灰；开启时按偏好——颜色模式用红/黄/绿，文字模式保持中性。
    private var levelColor: Color {
        guard isOn else { return theme.inkSecondary }
        if useColorIndicator {
            switch demoLevel {
            case .low: return theme.signalGood
            case .medium: return theme.signalWarn
            case .high: return theme.signalBad
            }
        }
        return theme.inkSecondary
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
