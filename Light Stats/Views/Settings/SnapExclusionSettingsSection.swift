//
//  SnapExclusionSettingsSection.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// Apps the snap engine must leave alone.
///
/// Two tiers, and the distinction matters. The built-in `restricted` list is short and contains
/// only apps that genuinely break when a third party moves their windows — media players, games,
/// remote desktops. Chrome, Firefox, Finder, Preview, and every Electron chat client sit in the same
/// category, but those are windows people snap constantly; shipping that as a default would
/// make the feature look broken rather than careful. So it is offered here as one button.
struct SnapExclusionSettingsSection: View {

    @Environment(\.theme) private var theme
    @ObservedObject var settings: SettingsManager
    @State private var selection: String?
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup {
                SettingsRow(
                    "settings.snap.exclusions.restricted".localized,
                    subtitle: "settings.snap.exclusions.restrictedHint".localized
                ) {
                    SettingsToggle(isOn: $settings.windowSnap.honorsRestrictedApps)
                }
            }

            list

            Text("settings.snap.exclusions.hint".localized)
                .font(.system(size: 10))
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("settings.snap.exclusions.title".localized)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(theme.inkFaint)
                Spacer(minLength: 8)
                Button("settings.snap.exclusions.addRecommended".localized) {
                    addRecommended()
                }
                .controlSize(.small)
            }

            VStack(spacing: 0) {
                rows
                Divider()
                footer
            }
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.usesVibrantSurfaces ? Color(nsColor: .controlBackgroundColor) : theme.surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(theme.surfaceStroke)
            )
        }
    }

    @ViewBuilder
    private var rows: some View {
        let exclusions = settings.windowSnap.exclusions
        if exclusions.isEmpty {
            Text("settings.snap.exclusions.empty".localized)
                .font(.system(size: 10))
                .foregroundStyle(theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .padding(.horizontal, 10)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(exclusions, id: \.self) { bundleID in
                        row(bundleID)
                        if bundleID != exclusions.last {
                            Divider().padding(.leading, 10)
                        }
                    }
                }
            }
            .frame(height: 118)
        }
    }

    private func row(_ bundleID: String) -> some View {
        HStack(spacing: 10) {
            Text(displayName(for: bundleID))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .layoutPriority(1)
            Text(bundleID)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(bundleID))
        .contentShape(Rectangle())
        .onTapGesture { selection = bundleID }
        .onHover { hovered = $0 ? bundleID : (hovered == bundleID ? nil : hovered) }
    }

    private func rowBackground(_ bundleID: String) -> Color {
        if selection == bundleID { return Color.accentColor.opacity(0.18) }
        if hovered == bundleID { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var footer: some View {
        HStack(spacing: 2) {
            gutterButton("plus", enabled: true) { addFromRunningApp() }
            gutterButton("minus", enabled: selection != nil) {
                guard let selection else { return }
                var configuration = settings.windowSnap
                configuration.exclusions.removeAll { $0 == selection }
                settings.windowSnap = configuration
                self.selection = nil
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

    // MARK: - Mutations

    /// Adds the frontmost app other than ourselves. Picking from a live list would need a picker
    /// with icons; adding what the user is currently looking at is the common case and one click.
    private func addFromRunningApp() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != selfPID,
              let bundleID = frontmost.bundleIdentifier else { return }
        add(bundleID)
    }

    private func addRecommended() {
        var configuration = settings.windowSnap
        let merged = Set(configuration.exclusions).union(SnapWindowEligibility.recommendedExclusionSet)
        configuration.exclusions = merged.sorted()
        settings.windowSnap = configuration
    }

    private func add(_ bundleID: String) {
        var configuration = settings.windowSnap
        guard !configuration.exclusions.contains(bundleID) else { return }
        configuration.exclusions.append(bundleID)
        settings.windowSnap = configuration
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}
