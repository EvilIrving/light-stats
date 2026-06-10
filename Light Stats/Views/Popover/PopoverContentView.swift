import SwiftUI

struct PopoverContentView: View {
    @State private var selectedTab: Int = 0
    @Namespace private var animation
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var hoveredIcon: String?
    @Environment(\.openSettings) private var openSettingsAction

    private var preset: AppearancePreset { settings.appearancePreset }
    private var layout: AppLayout { preset.layout }
    private var theme: AppTheme { preset.theme }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar

            ZStack {
                if selectedTab == 0 {
                    overviewContent.transition(.opacity)
                } else {
                    CleanupTabView().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(panelBackground.ignoresSafeArea())
        .frame(width: layout.popoverSize.width, height: layout.popoverSize.height)
        .cornerRadius(theme.cornerRadius)
        .preferredColorScheme(theme.forceDarkAppearance ? .dark : nil)
        .environment(\.appTheme, theme)
        .id(localization.currentLanguage)
    }

    // MARK: - Navigation Bar

    @ViewBuilder
    private var navigationBar: some View {
        switch layout.navigationStyle {
        case .topTabs:
            topTabsNav
        case .floatingSegment:
            floatingSegmentNav
        case .compactHeader:
            compactHeaderNav
        case .iconOnlyBottom:
            EmptyView() // Bottom nav rendered separately
        }
    }

    private var topTabsNav: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                TabButton(title: "tab.overview".localized, isSelected: selectedTab == 0, namespace: animation) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedTab = 0 }
                }
                TabButton(title: "tab.cleanup".localized, isSelected: selectedTab == 1, namespace: animation) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedTab = 1 }
                }
            }
            .padding(3)
            .background(
                Capsule().fill(theme.primaryText.opacity(0.04))
            )
            Spacer()
            iconButtons
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var floatingSegmentNav: some View {
        HStack {
            Spacer()
            HStack(spacing: 0) {
                tabPill("tab.overview".localized, index: 0)
                tabPill("tab.cleanup".localized, index: 1)
            }
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
            Spacer()
        }
        .overlay(alignment: .trailing) {
            iconButtons
                .padding(.trailing, layout.horizontalPadding)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func tabPill(_ title: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedTab = index }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundColor(selectedTab == index ? theme.primaryText : theme.secondaryText.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selectedTab == index ? theme.accent.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var compactHeaderNav: some View {
        HStack(spacing: 0) {
            Text(selectedTab == 0 ? "tab.overview".localized : "tab.cleanup".localized)
                .font(.system(size: 12, weight: .bold, design: theme.fontDesign))
                .foregroundColor(theme.primaryText)
            Spacer()
            HStack(spacing: 2) {
                Button { withAnimation(.easeInOut(duration: 0.12)) { selectedTab = 0 } } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 10))
                        .foregroundColor(selectedTab == 0 ? theme.accent : theme.secondaryText.opacity(0.4))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)

                Button { withAnimation(.easeInOut(duration: 0.12)) { selectedTab = 1 } } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 10))
                        .foregroundColor(selectedTab == 1 ? theme.accent : theme.secondaryText.opacity(0.4))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(theme.card.opacity(theme.cardOpacity))
            )
            iconButtons
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var iconButtons: some View {
        HStack(spacing: 4) {
            iconButton("gear.circle.fill", help: "tab.settings".localized, id: "settings") { openSettings() }
            iconButton("info.circle.fill", help: "About", id: "about") { openAbout() }
            iconButton("xmark.circle.fill", help: "Quit", id: "quit") { NSApp.terminate(nil) }
        }
    }

    private func iconButton(_ systemName: String, help: String, id: String, action: @escaping () -> Void) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16))
            .foregroundColor(hoveredIcon == id ? theme.secondaryText : theme.secondaryText.opacity(0.5))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .help(help)
            .onHover { hoveredIcon = $0 ? id : nil }
            .onTapGesture { action() }
    }

    // MARK: - Overview Dispatch

    @ViewBuilder
    private var overviewContent: some View {
        switch layout.overviewStyle {
        case .cards:
            ClassicOverviewView()
        case .compactGrid:
            compactLayout
        case .terminalRows:
            TerminalOverviewView()
        case .glassCards:
            GlassOverviewView()
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            compactHeaderNav
            CompactOverviewView()
            compactBottomNav
        }
    }

    private var compactBottomNav: some View {
        HStack(spacing: 0) {
            bottomNavIcon("chart.bar.fill", index: 0)
            Spacer()
            bottomNavIcon("trash.fill", index: 1)
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 4)
        .background(
            Rectangle()
                .fill(theme.primaryText.opacity(0.03))
                .frame(height: 1),
            alignment: .top
        )
    }

    private func bottomNavIcon(_ systemName: String, index: Int) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(selectedTab == index ? theme.accent : theme.secondaryText.opacity(0.3))
            .frame(width: 32, height: 28)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.12)) { selectedTab = index } }
    }

    // MARK: - Background

    @ViewBuilder
    private var panelBackground: some View {
        if theme.background == Color.clear || theme.panelMaterial == .hudWindow {
            VisualEffectView(material: theme.panelMaterial, blendingMode: .behindWindow)
        } else {
            VisualEffectView(material: theme.panelMaterial, blendingMode: .behindWindow)
        }
    }

    // MARK: - Actions

    private func openSettings() {
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { openSettingsAction() }
    }

    private func openAbout() {
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .showAbout, object: nil)
        }
    }

    private func closePanel() {
        (NSApp.delegate as? AppDelegate)?.closePanel()
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
