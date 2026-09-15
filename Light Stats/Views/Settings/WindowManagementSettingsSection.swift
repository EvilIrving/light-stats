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

    var body: some View {
        SettingsDetailScaffold("settings.windowManagement".localized) {
            SettingsGroup {
                SettingsRow("settings.windowManagement".localized) {
                    SettingsToggle(isOn: $settings.windowManagementEnabled)
                }
            }

            if settings.windowManagementEnabled && !hasAccessibility {
                SnapPermissionNotice()
            }

            if settings.windowManagementEnabled {
                SnapInteractionPreview(settings: settings)
                SnapBehaviourSettingsSection(settings: settings)
                if settings.windowSnap.zones.topEdgeMode == .island {
                    SnapIslandSettingsSection(settings: settings)
                }
                SnapLayoutSettingsSection(settings: settings)
                SnapWindowPreviewSettingsSection(settings: settings)
                DisclosureGroup("settings.snap.shortcuts.title".localized) {
                    SnapShortcutSettingsSection(settings: settings).padding(.top, 10)
                }
                DisclosureGroup("settings.snap.exclusions.title".localized) {
                    SnapExclusionSettingsSection(settings: settings).padding(.top, 10)
                }
                SnapSystemTilingSettingsSection(settings: settings)
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

/// Drag zones, gaps, the preview overlay, and which implementation places the window.
struct SnapBehaviourSettingsSection: View {

    @ObservedObject var settings: SettingsManager

    var body: some View {
        SettingsSection("settings.snap.behaviour".localized) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsGroup {
                    SettingsRow("settings.snap.edgeSnap".localized) {
                        SettingsToggle(isOn: $settings.windowSnap.zones.edgesEnabled)
                    }
                    rowDivider()
                    SettingsRow("settings.snap.cornerSnap".localized) {
                        SettingsToggle(isOn: $settings.windowSnap.zones.cornersEnabled)
                    }
                    rowDivider()
                    SettingsRow("settings.snap.topEdge".localized) {
                        SettingsSegmentedPicker(selection: $settings.windowSnap.zones.topEdgeMode, segmentMinWidth: 52) {
                            ForEach(SnapTopEdgeMode.allCases, id: \.self) { mode in
                                SettingsSegmentLabel(title: label(for: mode)).tag(mode)
                            }
                        }
                    }
                    rowDivider()
                    SettingsRow("settings.snap.preview".localized) {
                        SettingsToggle(isOn: $settings.windowSnap.showsPreview)
                    }
                    rowDivider()
                    SettingsRow("settings.snap.shakeToHide".localized) {
                        SettingsToggle(isOn: $settings.windowSnap.isShakeToHideEnabled)
                    }
                    rowDivider()
                    SettingsRow(
                        "settings.snap.nativeTiling".localized,
                        subtitle: "settings.snap.nativeTiling.hint".localized
                    ) {
                        SettingsToggle(isOn: $settings.windowSnap.prefersNativeTiling)
                    }
                }

                SettingsGroup {
                    gapRow("settings.snap.gapInner".localized, kind: .inner)
                    rowDivider()
                    gapRow("settings.snap.gapOuter".localized, kind: .outer)
                }
            }
        }
    }

    /// Which of the two gaps a row edits.
    enum GapKind {
        case inner
        case outer
    }

    /// The slider tracks a local value and only writes the configuration when the drag ends.
    ///
    /// Writing on every tick would persist the whole JSON blob — and log a settings change — dozens
    /// of times per second while the user is still choosing a number.
    private func gapRow(_ title: String, kind: GapKind) -> some View {
        let bound = kind == .inner ? settings.windowSnap.margins.inner : settings.windowSnap.margins.outer
        return GapSlider(
            title: title,
            value: bound,
            onCommit: { commit($0, kind: kind) }
        )
    }

    private func commit(_ value: CGFloat, kind: GapKind) {
        var configuration = settings.windowSnap
        let margins = configuration.margins
        configuration.margins = kind == .inner
            ? SnapMargins(outer: margins.outer, inner: value)
            : SnapMargins(outer: value, inner: margins.inner)
        guard configuration.margins != margins else { return }
        settings.windowSnap = configuration
    }

    private func label(for mode: SnapTopEdgeMode) -> String {
        switch mode {
        case .island: return "settings.snap.topEdge.island".localized
        case .maximize: return "settings.snap.topEdge.maximize".localized
        case .disabled: return "settings.snap.topEdge.off".localized
        }
    }
}

// MARK: - Island

/// How the layout island looks.
struct SnapIslandSettingsSection: View {

    @ObservedObject var settings: SettingsManager

    var body: some View {
        SettingsSection("settings.snap.island".localized) {
            SettingsGroup {
                SettingsRow("settings.snap.island.palette".localized) {
                    SettingsSegmentedPicker(selection: $settings.windowSnap.islandPalette, segmentMinWidth: 56) {
                        ForEach(SnapIslandMetrics.Palette.allCases, id: \.self) { palette in
                            Image(systemName: "circle.fill")
                                .foregroundStyle(palette == .accent ? Color.accentColor : (palette == .vivid ? .white : .gray))
                                .accessibilityLabel(label(for: palette))
                                .tag(palette)
                        }
                    }
                }
            }
        }
    }

    private func label(for palette: SnapIslandMetrics.Palette) -> String {
        switch palette {
        case .neutral: return "settings.snap.island.palette.neutral".localized
        case .accent: return "settings.snap.island.palette.accent".localized
        case .vivid: return "settings.snap.island.palette.vivid".localized
        }
    }
}

// MARK: - System tiling

/// macOS' own drag-to-edge tiling, plus the warning when both implementations are live.
struct SnapSystemTilingSettingsSection: View {

    @Environment(\.theme) private var theme
    @ObservedObject var settings: SettingsManager
    @StateObject private var systemTiling = SystemWindowTilingSettings()
    @State private var otherManagers: [String] = []

    var body: some View {
        SettingsSection("settings.systemTiling".localized) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsGroup {
                    SettingsRow(
                        "settings.systemTiling.edgeDrag".localized,
                        subtitle: "settings.systemTiling.description".localized
                    ) {
                        SettingsToggle(isOn: $systemTiling.edgeDragEnabled)
                    }
                    rowDivider()
                    SettingsRow("settings.systemTiling.topEdgeDrag".localized) {
                        SettingsToggle(isOn: $systemTiling.topEdgeDragEnabled)
                    }
                }

                if systemTiling.edgeDragEnabled && settings.windowSnap.isDragSnappingActive {
                    conflictNotice(
                        message: "settings.snap.conflict".localized,
                        actionTitle: "settings.snap.conflict.resolve".localized,
                        action: { systemTiling.edgeDragEnabled = false }
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
        }
        .onAppear {
            systemTiling.reload()
            otherManagers = SnapConflictDetector.runningConflictNames()
        }
    }

    /// Two implementations of one gesture being live is the single most likely cause of "it snapped
    /// somewhere random", so it is called out rather than left to be discovered.
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
}
