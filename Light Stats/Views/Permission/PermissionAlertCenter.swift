//
//  PermissionAlertCenter.swift
//  Light Stats
//

import AppKit

extension AccessibilityPermission {
    /// Presents the standard system permission guide with no app-theme dependency.
    ///
    /// The two buttons stay because the alert is the only place a service failure can explain
    /// itself. What changed is where "Open System Settings" leads: the guide opens the pane *and*
    /// shows the user what to do there, instead of leaving them in a list with nothing to click.
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
        // The alert is modal and has just ended: there is no window to fly from, so the card fades in
        // where it docks.
        PermissionGuideCenter.shared.present(pane: .accessibility, anchor: nil)
    }
}
