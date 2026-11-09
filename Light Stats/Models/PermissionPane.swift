//
//  PermissionPane.swift
//  Light Stats
//

import Foundation

/// The two Privacy panes this app asks the user to drag itself into.
///
/// The pane owns its own deep link, the name shown in the card's sentence, and the owner names a
/// System Settings window can carry — so a pane is one value to add rather than three constants to
/// keep in step in three files.
nonisolated enum PermissionPane: String, Sendable, CaseIterable {

    case accessibility
    case screenRecording

    /// `x-apple.systempreferences:` deep links, one per pane. Stable across releases; only the
    /// panes' human titles get renamed by Apple.
    var settingsURLString: String {
        switch self {
        case .accessibility: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording: return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
    }

    var url: URL? {
        URL(string: settingsURLString)
    }

    /// Localized name of the privacy service, for the card's one sentence.
    var displayNameKey: String {
        switch self {
        case .accessibility: return "permission.guide.pane.accessibility"
        case .screenRecording: return "permission.guide.pane.screenRecording"
        }
    }

    /// The System Settings bundle identifier — the reliable way to recognise the app.
    ///
    /// The window-list owner *name* is localized: on a machine whose system language is Chinese,
    /// `kCGWindowOwnerName` reports 系统设置, not "System Settings". Matching by name alone works
    /// only on an English system, which is why the identifier is the primary test and the names are
    /// a fallback for the moment before LaunchServices reports the process.
    static let settingsBundleIdentifier = "com.apple.systempreferences"

    /// The owner names a System Settings window may report through `kCGWindowOwnerName`.
    ///
    /// Kept as the fallback above. `System Preferences` covers macOS 12 and anything else still
    /// opening the pre-Ventura shell.
    static let settingsOwnerNames: Set<String> = ["System Settings", "System Preferences"]

    static func isSettingsOwner(_ ownerName: String) -> Bool {
        settingsOwnerNames.contains(ownerName)
    }
}
