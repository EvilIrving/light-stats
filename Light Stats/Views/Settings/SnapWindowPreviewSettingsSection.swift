//
//  SnapWindowPreviewSettingsSection.swift
//  Light Stats
//

import SwiftUI

/// The window-preview switches: thumbnails, the Dock hover preview, and ⌘Tab.
///
/// Three switches rather than one, because they cost different things. The Dock preview and ⌘Tab
/// work with nothing but Accessibility and degrade to titles and icons without a picture; only the
/// thumbnail switch asks for Screen Recording, and it says so on the row that would trigger it
/// rather than surprising the user with a system prompt from an unrelated toggle.
struct SnapWindowPreviewSettingsSection: View {

    @ObservedObject var settings: SettingsManager

    @State private var authorization: ScreenRecordingAuthorization = .denied

    var body: some View {
        SettingsSection("settings.snap.previews".localized) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsGroup {
                    SettingsRow(
                        "settings.snap.thumbnails".localized,
                        subtitle: "settings.snap.thumbnails.hint".localized
                    ) {
                        SettingsToggle(isOn: thumbnailsBinding)
                    }
                    rowDivider()
                    SettingsRow(
                        "settings.snap.dockPreview".localized,
                        subtitle: "settings.snap.dockPreview.hint".localized
                    ) {
                        SettingsToggle(isOn: $settings.windowSnap.isDockPreviewEnabled)
                    }
                    rowDivider()
                    SettingsRow(
                        "settings.snap.commandTab".localized,
                        subtitle: "settings.snap.commandTab.hint".localized
                    ) {
                        SettingsToggle(isOn: $settings.windowSnap.isCommandTabPlusEnabled)
                    }
                }

                if settings.windowSnap.isWindowThumbnailsEnabled, authorization != .authorized {
                    screenRecordingNotice
                }

                if settings.windowSnap.isCommandTabPlusEnabled {
                    Text("settings.snap.commandTab.warning".localized)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear(perform: refreshAuthorization)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAuthorization()
        }
    }

    // MARK: - Thumbnails and the permission

    /// Turning thumbnails on asks for the permission there and then, which is the only moment the
    /// system prompt is not a surprise.
    private var thumbnailsBinding: Binding<Bool> {
        Binding(
            get: { settings.windowSnap.isWindowThumbnailsEnabled },
            set: { enabled in
                var configuration = settings.windowSnap
                guard configuration.isWindowThumbnailsEnabled != enabled else { return }
                configuration.isWindowThumbnailsEnabled = enabled
                settings.windowSnap = configuration
                guard enabled else { return }
                ScreenRecordingPermission.markRequested()
                _ = ScreenRecordingPermission.request()
                refreshAuthorization()
            }
        )
    }

    private var screenRecordingNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "rectangle.dashed.badge.record")
                .foregroundStyle(themeWarn)
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.snap.screenRecording.needed".localized)
                    .font(.system(size: 12, weight: .medium))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if authorization == .requiresRestart {
                Button("settings.snap.screenRecording.relaunch".localized) {
                    ApplicationRelaunch.relaunch { _ in }
                }
                .controlSize(.small)
            }
            Button("cleaning.permission.openSettings".localized) {
                ScreenRecordingPermission.markRequested()
                ScreenRecordingPermission.openSettings()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(themeWarn.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(themeWarn.opacity(0.28))
        )
    }

    private var message: String {
        switch authorization {
        case .requiresRestart:
            return "settings.snap.screenRecording.requiresRestart".localized
        case .authorized, .denied:
            return "settings.snap.screenRecording.denied".localized
        }
    }

    private var themeWarn: Color { Color.orange }

    private func refreshAuthorization() {
        authorization = ScreenRecordingAuthorization.resolve(
            isGranted: ScreenRecordingPermission.isGranted,
            hasRequestedThisSession: ScreenRecordingPermission.hasBeenRequested
        )
    }
}
