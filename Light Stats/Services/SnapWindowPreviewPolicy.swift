//
//  SnapWindowPreviewPolicy.swift
//  Light Stats
//

import Foundation

/// Whether the window-preview group — thumbnails, the Dock hover preview, and ⌘Tab — is offered.
///
/// The three surfaces are not finished yet, so the product ships them **hidden and inert**: the
/// switches are not drawn, and the wiring refuses to start the Dock hover poll or the ⌘Tab event tap
/// no matter what a stored preference says. Hiding the rows alone would not be enough — the Dock
/// preview and ⌘Tab both default to on, so an unfinished surface would keep running with no way for
/// the user to turn it off, and ⌘Tab takes a system gesture away while it does.
///
/// Flipping `isAvailable` to `true` is the entire switch-on. Stored preferences are left alone
/// rather than rewritten, so a user who had a surface on gets it back when it ships.
enum SnapWindowPreviewPolicy {

    /// One of the three preview surfaces, each costing something different.
    enum Surface: String, CaseIterable, Sendable {
        /// Pictures instead of titles and icons. The only surface that needs Screen Recording.
        case thumbnails
        /// The panel that follows the pointer along the Dock.
        case dockPreview
        /// Replacing the system application switcher.
        case commandTab

        /// The stored preference that owns this surface.
        func isEnabled(in configuration: SnapConfiguration) -> Bool {
            switch self {
            case .thumbnails: return configuration.isWindowThumbnailsEnabled
            case .dockPreview: return configuration.isDockPreviewEnabled
            case .commandTab: return configuration.isCommandTabPlusEnabled
            }
        }
    }

    /// `false` until the three surfaces are finished.
    static let isAvailable = false

    /// Whether a surface should actually run.
    ///
    /// `available` is injected so the rule can be tested in both directions; production callers use
    /// the default.
    static func isActive(
        _ surface: Surface,
        configuration: SnapConfiguration,
        windowManagementEnabled: Bool,
        available: Bool = isAvailable
    ) -> Bool {
        guard available, windowManagementEnabled else { return false }
        return surface.isEnabled(in: configuration)
    }
}
