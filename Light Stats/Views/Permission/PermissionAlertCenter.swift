//
//  PermissionAlertCenter.swift
//  Light Stats
//

import AppKit

extension AccessibilityPermission {
    /// Presents the standard system permission guide with no app-theme dependency.
    @MainActor
    static func presentSettingsAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "cleaning.permission.openSettings".localized)
        alert.addButton(withTitle: "update.action.later".localized)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        openSettings()
    }
}
