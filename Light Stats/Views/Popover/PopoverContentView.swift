//
//  PopoverContentView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI
struct PopoverContentView: View {
    @State private var selectedTab: Int = 0
    @Namespace private var animation
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.openSettings) private var openSettingsAction
    @State private var hoveredIcon: String?

    /// Resolved at this root from settings — `@Environment(\.theme)` only reaches children
    /// after `.appThemed`, so the root itself must not depend on it.
    private var theme: ThemeTokens { ThemeTokens.tokens(for: settings.appTheme) }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    TabButton(title: "tab.overview".localized, isSelected: selectedTab == 0, namespace: animation) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedTab = 0
                        }
                    }

                    TabButton(title: "tab.cleanup".localized, isSelected: selectedTab == 1, namespace: animation) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedTab = 1
                        }
                    }
                }
                .padding(3)
                .background(
                    Capsule()
                        .fill(theme.tabTrackFill)
                )

                Spacer()

                HStack(spacing: 4) {
#if DEBUG
                    toolbarIcon(
                        systemName: "camera.circle.fill",
                        key: "snapshot"
                    ) { DebugSnapshot.dumpPanel() }
#endif
                    // 擦屏模式锁内置键盘，仅对带内置键盘的便携机型（MacBook）有意义；
                    // Mac mini / Studio / iMac 等台式机无内置键盘，隐藏入口。
                    if DeviceCapabilities.isPortable {
                        toolbarIcon(
                            image: "cleaningLock",
                            key: "cleaning",
                            iconSize: 15
                        ) { CleaningModeViewModel.shared.start() }
                    }

                    toolbarIcon(
                        systemName: "gearshape",
                        key: "settings",
                        iconSize: 15,
                        weight: .medium
                    ) { openSettings() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // Content Area
            ZStack {
                if selectedTab == 0 {
                    OverviewTabView()
                        .transition(.opacity)
                } else {
                    CleanupTabView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .ignoresSafeArea(.container, edges: .top)
        // Mesh art + grain live entirely inside ThemeBackgroundView (soft center
        // veil only). No full-frame scrim — that was burying light shapes + grit.
        // ThemeBackgroundView’s mesh path keeps a solid canvas under decorative art
        // so wheel events cannot fall through the non-opaque panel (film/noir).
        .background(
            ThemeBackgroundView(
                tokens: theme,
                appearance: settings.themeAppearance(for: settings.appTheme),
                cornerRadius: 12
            )
                .ignoresSafeArea()
        )
        .frame(width: 360, height: 780)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .cornerRadius(12)
        // Language + theme: mesh↔mesh (film/noir) must rebuild chrome, not only language.
        .id("\(localization.currentLanguage.rawValue)/\(settings.appTheme.rawValue)")
        .appThemed(settings.appTheme)
        .focusable(false)
        .overlayPreferenceValue(ToolbarIconBoundsKey.self) { anchors in
            GeometryReader { proxy in
                if let key = hoveredIcon,
                   let text = tooltipText(for: key),
                   let anchor = anchors[key] {
                    let rect = proxy[anchor]
                    tooltipLabel(text)
                        .position(x: rect.midX, y: rect.maxY + tooltipGap)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Tooltip (root-level overlay, positioned from measured icon anchors)

    /// tooltip 与图标底边的垂直间距——唯一可调常量，水平/垂直定位均由 anchor 实测。
    private var tooltipGap: CGFloat { 16 }

    private func tooltipLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.inkPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.usesGlass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(theme.cardFill))
                    .shadow(color: .black.opacity(theme.cardShadowOpacity + 0.06), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(theme.cardStroke, lineWidth: 0.5)
            )
            .fixedSize()
    }

    private func tooltipText(for key: String) -> String? {
        switch key {
        case "snapshot": return "导出截图"
        case "cleaning": return "cleaning.action.start".localized
        case "settings": return "popover.action.settings".localized
        default: return nil
        }
    }

    private func openSettings() {
        (NSApp.delegate as? AppDelegate)?.closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            openSettingsAction()
        }
    }

    // MARK: - Toolbar Icons (hover only, tooltip rendered at root level)

    private func toolbarIcon(
        systemName: String? = nil,
        image: String? = nil,
        key: String,
        iconSize: CGFloat = 16,
        weight: Font.Weight = .regular,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: weight))
            } else if let image {
                Image(image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            }
        }
        .foregroundStyle(hoveredIcon == key ? theme.inkSecondary : theme.inkFaint)
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
        .anchorPreference(key: ToolbarIconBoundsKey.self, value: .bounds) { [key: $0] }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredIcon = hovering ? key : nil
            }
        }
        .onTapGesture(perform: action)
    }
}

/// 收集每个工具栏图标在根坐标空间中的实测边界，供根层 tooltip overlay 精确定位。
private struct ToolbarIconBoundsKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension Notification.Name {
    static let showAbout = Notification.Name("showAbout")
}

#if DEBUG
#Preview {
    PopoverContentView()
}
#endif
