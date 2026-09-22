//
//  SnapDockClickSettingsSection.swift
//  Light Stats
//

import SwiftUI

/// The Dock-click toggle: clicking a running app's icon puts its windows away and brings them back.
///
/// Its own section rather than a row inside the drags section, because it is the one window-management
/// feature that is reached from the Dock instead of from a window, and a user looking for it looks for
/// "Dock".
struct SnapDockClickSettingsSection: View {

    @ObservedObject var settings: SettingsManager

    var body: some View {
        SettingsSection("settings.snap.dock.title".localized) {
            SettingsGroup {
                SettingsRow(
                    "settings.snap.dock.collapse".localized,
                    subtitle: "settings.snap.dock.collapse.hint".localized
                ) {
                    SettingsToggle(isOn: $settings.windowSnap.isDockClickCollapseEnabled)
                }
            }
        }
    }
}
