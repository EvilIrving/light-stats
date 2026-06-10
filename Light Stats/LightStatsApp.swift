import SwiftUI

@main
struct LightStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = SettingsManager.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(\.appTheme, settings.appearancePreset.theme)
        }
    }
}
