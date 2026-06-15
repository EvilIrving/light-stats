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
    @State private var hoveredIcon: String? = nil
    @Environment(\.openSettings) private var openSettingsAction

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
                        .fill(Color.primary.opacity(0.03))
                )

                Spacer()

                // Icons: Settings, About, Quit
                HStack(spacing: 4) {
#if DEBUG
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(hoveredIcon == "snapshot" ? .secondary : .secondary.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .help("导出完整面板截图到 docs/screenshots（DEBUG）")
                        .onHover { hoveredIcon = $0 ? "snapshot" : nil }
                        .onTapGesture { DebugSnapshot.dumpPanel() }
#endif

                    Image(systemName: "gear.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(hoveredIcon == "settings" ? .secondary : .secondary.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .help("tab.settings".localized)
                        .onHover { hoveredIcon = $0 ? "settings" : nil }
                        .onTapGesture { openSettings() }

                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(hoveredIcon == "about" ? .secondary : .secondary.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .help("About")
                        .onHover { hoveredIcon = $0 ? "about" : nil }
                        .onTapGesture { openAbout() }

                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(hoveredIcon == "quit" ? .secondary : .secondary.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .help("Quit")
                        .onHover { hoveredIcon = $0 ? "quit" : nil }
                        .onTapGesture { NSApp.terminate(nil) }
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
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(GlassBackgroundView(cornerRadius: 12).ignoresSafeArea())
        .frame(width: 360, height: 520)
        .cornerRadius(12)
        .id(localization.currentLanguage) // Force refresh when language changes
    }

    // MARK: - Actions

    private func openSettings() {
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            openSettingsAction()
        }
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
