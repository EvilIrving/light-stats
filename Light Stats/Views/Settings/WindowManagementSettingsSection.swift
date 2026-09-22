//
//  WindowManagementSettingsSection.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import SwiftUI

// MARK: - Window Management

/// The whole window-management page.
///
/// Everything that belongs to window management lives here — behaviour, the island, shortcuts,
/// layouts, exclusions, and the system's own tiling switch — rather than being scattered across
/// other sections. The single master switch at the top is still the only thing that starts or stops
/// the pipeline.
struct WindowManagementDetail: View {
    @ObservedObject var settings: SettingsManager
    @State private var hasAccessibility = AccessibilityPermission.isTrusted()

    /// The drag demo is only meaningful while our own pipeline owns the gesture.
    private var showsDragDemo: Bool {
        settings.windowManagementEnabled && settings.windowSnap.edgeOwner == .lightStats
    }

    var body: some View {
        SettingsDetailScaffold("settings.windowManagement".localized) {
            // The master switch keeps the full width at the top: it is the one control that turns the
            // whole feature on. Splitting the columns below it is also what puts the practice area
            // level with the drag rows rather than level with the switch.
            SettingsGroup {
                SettingsRow("settings.windowManagement".localized) {
                    SettingsToggle(isOn: $settings.windowManagementEnabled)
                }
            }

            if settings.windowManagementEnabled {
                // 标题横跨两列：练习场跟左边的设置行是同一件事的两面，所以它的上边缘要跟卡片
                // 齐平，而不是跟标题齐平，更不能跑到「窗口管理」总开关那一行去。
                SettingsSection("settings.snap.behaviour".localized) {
                    HStack(alignment: .top, spacing: 16) {
                        SnapBehaviourSettingsSection(settings: settings)
                            .frame(maxWidth: showsDragDemo ? 320 : .infinity, alignment: .topLeading)

                        if showsDragDemo {
                            // 练习场不是设置项，也永远不带标题；只有代码需要知道它是什么。
                            SnapInteractionPreview(settings: settings)
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
            }

            if settings.windowManagementEnabled && !hasAccessibility {
                SnapPermissionNotice()
            }

            if settings.windowManagementEnabled {
                SnapDockClickSettingsSection(settings: settings)
                SnapLayoutSettingsSection(settings: settings)
                SnapWindowPreviewSettingsSection(settings: settings)
                DisclosureGroup("settings.snap.shortcuts.title".localized) {
                    SnapShortcutSettingsSection(settings: settings).padding(.top, 10)
                }
                DisclosureGroup("settings.snap.exclusions.title".localized) {
                    SnapExclusionSettingsSection(settings: settings).padding(.top, 10)
                }
            }
        }
        .onAppear { hasAccessibility = AccessibilityPermission.isTrusted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have just granted it in System Settings; the notice should disappear
            // without them having to close and reopen the pane.
            hasAccessibility = AccessibilityPermission.isTrusted()
        }
    }
}

// MARK: - Permission

/// Shown while window management is on and Accessibility has not been granted.
///
/// A banner rather than a modal alert: the modal fires once when a service fails to start, which is
/// the wrong moment to explain a permission — the user has moved on to something else by then, or
/// has not asked for the feature yet.
struct SnapPermissionNotice: View {

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(theme.signalWarn)
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.snap.permission.title".localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.inkPrimary)
                Text("settings.snap.permission.message".localized)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("cleaning.permission.openSettings".localized) {
                AccessibilityPermission.openSettings()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.signalWarn.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.signalWarn.opacity(0.28))
        )
    }
}

// MARK: - Behaviour

/// Who owns drag-to-edge, which zones are live, and which implementation places the window.
///
/// Placement preview, island palette, and gaps stay on their defaults — they are product choices,
/// not preferences the settings page needs to expose. The gap is fixed at zero, so our placement
/// and the system's cannot disagree about spacing if the user changes their mind.
struct SnapBehaviourSettingsSection: View {

    @Environment(\.theme) private var theme
    @ObservedObject var settings: SettingsManager
    @StateObject private var systemTiling = SystemWindowTilingSettings()
    @State private var otherManagers: [String] = []

    var body: some View {
        // 标题在调用方：它要横跨设置列和练习场两列，这里只剩卡片和冲突提示。
        VStack(alignment: .leading, spacing: 10) {
            SettingsGroup {
                // Before macOS 15 there is only one implementation, so there is no choice to
                // offer — and offering one would let the user pick a side that does not exist.
                if SystemWindowTilingSetting.isAvailable {
                    SettingsRow(
                        "settings.snap.edgeOwner".localized,
                        subtitle: "settings.snap.edgeOwner.hint".localized,
                        stacksControl: true
                    ) {
                        SettingsSegmentedPicker(selection: $settings.windowSnap.edgeOwner, segmentMinWidth: 76) {
                            ForEach(SnapEdgeOwner.allCases, id: \.self) { owner in
                                SettingsSegmentLabel(title: label(for: owner)).tag(owner)
                            }
                        }
                    }
                }
                // With macOS owning the gesture these do nothing, so they are not shown: a switch
                // that is visible and inert is worse than no switch at all.
                if zonesAreLive {
                    if SystemWindowTilingSetting.isAvailable { rowDivider() }
                    SettingsRow("settings.snap.edgeSnap".localized) {
                        SettingsToggle(isOn: $settings.windowSnap.zones.edgesEnabled)
                    }
                    rowDivider()
                    SettingsRow("settings.snap.cornerSnap".localized) {
                        SettingsToggle(isOn: $settings.windowSnap.zones.cornersEnabled)
                    }
                    rowDivider()
                    SettingsRow("settings.snap.topEdge".localized) {
                        SettingsSegmentedPicker(
                            selection: $settings.windowSnap.zones.topEdgeMode, segmentMinWidth: 52
                        ) {
                            ForEach(SnapTopEdgeMode.allCases, id: \.self) { mode in
                                SettingsSegmentLabel(title: label(for: mode)).tag(mode)
                            }
                        }
                    }
                }
                rowDivider()
                SettingsRow("settings.snap.shakeToHide".localized) {
                    SettingsToggle(isOn: $settings.windowSnap.isShakeToHideEnabled)
                }
            }

            if systemTiling.conflictsWithLightStats, settings.windowSnap.edgeOwner == .lightStats {
                conflictNotice(
                    message: "settings.snap.conflict".localized,
                    actionTitle: "settings.snap.conflict.resolve".localized,
                    action: { systemTiling.giveGestureBackToLightStats() }
                )
            }

            // The other half of the same failure: macOS owns the gesture but has had its own
            // switches turned off elsewhere, which leaves dragging doing nothing at all.
            if settings.windowSnap.edgeOwner == .system, !systemTiling.isSystemOwnershipIntact {
                conflictNotice(
                    message: "settings.snap.owner.systemOff".localized,
                    actionTitle: "settings.snap.owner.systemOff.resolve".localized,
                    action: { systemTiling.reassertSystemOwnership() }
                )
            }

            if !otherManagers.isEmpty {
                conflictNotice(
                    message: "settings.snap.conflict.otherApp".localized(otherManagers.joined(separator: ", ")),
                    actionTitle: nil,
                    action: nil
                )
            }
        }
        .onAppear {
            systemTiling.reload()
            otherManagers = SnapConflictDetector.runningConflictNames()
        }
        .onChange(of: settings.windowSnap.edgeOwner) { _, owner in
            systemTiling.adoptOwner(owner)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The switches behind these notices are edited in System Settings, so re-read on return
            // instead of making the user restart the app to clear a stale warning.
            systemTiling.reload()
        }
    }

    private var zonesAreLive: Bool {
        !SystemWindowTilingSetting.isAvailable || settings.windowSnap.edgeOwner == .lightStats
    }

    /// Two implementations of one gesture being live is the single most likely cause of "it snapped
    /// somewhere random", so it is called out rather than left to be discovered. It can only happen
    /// when the user turned the system's switch back on by hand.
    private func conflictNotice(message: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.signalWarn)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.signalWarn.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.signalWarn.opacity(0.28))
        )
    }

    private func label(for owner: SnapEdgeOwner) -> String {
        switch owner {
        case .lightStats: return "settings.snap.edgeOwner.lightStats".localized
        case .system: return "settings.snap.edgeOwner.system".localized
        }
    }

    private func label(for mode: SnapTopEdgeMode) -> String {
        switch mode {
        case .island: return "settings.snap.topEdge.island".localized
        case .maximize: return "settings.snap.topEdge.maximize".localized
        case .disabled: return "settings.snap.topEdge.off".localized
        }
    }
}
