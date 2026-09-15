//
//  SnapShortcutSettingsSection.swift
//  Light Stats
//

import SwiftUI

/// The shortcut table: one row per snap action, plus a row for every custom binding.
///
/// The previous build shipped six hardcoded bindings and no way to change them, so 13 of the 19
/// actions could only be reached through the menu bar. Every action is listed here, bound or not,
/// because a list of only the bound ones hides the fact that the rest exist.
struct SnapShortcutSettingsSection: View {

    @Environment(\.theme) private var theme
    @ObservedObject var settings: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            actionGroup
            visibilityGroup
            if !customBindings.isEmpty {
                customGroup
            }
        }
    }

    private var actionGroup: some View {
        SettingsGroup {
            ForEach(Array(WindowSnapAction.allCases.enumerated()), id: \.element) { index, action in
                if index > 0 { rowDivider() }
                row(for: .action(action), title: SnapIslandText.title(for: action))
            }
        }
    }

    private var visibilityGroup: some View {
        SettingsGroup {
            ForEach(Array(WindowVisibilityCommand.allCases.enumerated()), id: \.element) { index, command in
                if index > 0 { rowDivider() }
                row(for: .visibility(command), title: command.titleKey.localized)
            }
        }
    }

    private var customGroup: some View {
        SettingsGroup {
            ForEach(Array(customBindings.enumerated()), id: \.element.target) { index, shortcut in
                if index > 0 { rowDivider() }
                row(
                    for: shortcut.target,
                    title: SnapIslandText.title(for: shortcut.target, in: settings.windowSnap)
                        ?? shortcut.target.diagnosticName
                )
            }
        }
    }

    private func row(for target: SnapTarget, title: String) -> some View {
        let shortcut = settings.windowSnap.shortcut(for: target)
        return SettingsRow(title) {
            KeyComboRecorder(
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers,
                onRecord: { code, modifiers in
                    var configuration = settings.windowSnap
                    configuration.setShortcut(SnapShortcut(target: target, keyCode: code, modifiers: modifiers))
                    settings.windowSnap = configuration
                },
                onClear: { clear(target) }
            )
        }
    }

    private var customBindings: [SnapShortcut] {
        var seen = Set<SnapTarget>()
        let regions = settings.windowSnap.customLayouts.flatMap { $0.segments.map(\.rect) }
            + settings.windowSnap.savedPlacements.map(\.rect)
        return regions.compactMap { rect in
            let target = SnapTarget.region(rect)
            guard seen.insert(target).inserted else { return nil }
            return settings.windowSnap.shortcut(for: target)
        }
    }

    private func clear(_ target: SnapTarget) {
        var configuration = settings.windowSnap
        configuration.removeShortcut(for: target)
        settings.windowSnap = configuration
    }
}
