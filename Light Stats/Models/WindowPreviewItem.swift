//
//  WindowPreviewItem.swift
//  Light Stats
//

import ApplicationServices
import CoreGraphics

/// One window, as every preview surface needs it.
///
/// The menu bar's window list, the Dock hover preview, and the app switcher all show the same
/// thing: a window with a title, a place to aim at, and possibly a thumbnail. They used to be three
/// separate shapes; this is the one they share, so filtering, ordering, and the AX-plus-WindowServer
/// join only exist once.
nonisolated struct WindowPreviewItem: @unchecked Sendable, Identifiable {

    /// Stable across refreshes of the same window, so SwiftUI does not rebuild every card when a
    /// list is re-read.
    var id: String
    var title: String
    var isMinimized: Bool
    var isOnScreen: Bool
    /// Frame in Accessibility space.
    var frame: CGRect?
    var element: AXUIElement
    var processID: pid_t
    var appName: String
    var bundleIdentifier: String?
    /// WindowServer id when the owning process exposes one. The thumbnail service needs it to pick
    /// the right `SCWindow`; most apps return 0, which is why the join falls back to geometry.
    var windowID: CGWindowID?
    /// WindowServer snapshots resolve Accessibility only when the user acts on this window.
    var needsElementResolution: Bool = false

    static func identifier(processID: pid_t, windowID: CGWindowID?, element: AXUIElement) -> String {
        if let windowID {
            return "\(processID)-win-\(windowID)"
        }
        return "\(processID)-ax-\(CFHash(element))"
    }
}

/// An application plus the windows of it that are worth previewing.
nonisolated struct ApplicationWindowGroup: @unchecked Sendable, Identifiable {

    var id: pid_t { processID }
    var processID: pid_t
    var appName: String
    var bundleIdentifier: String?
    var windows: [WindowPreviewItem]

    /// A display name that is never empty, so a card header cannot render as blank.
    var displayName: String {
        if !appName.isEmpty { return appName }
        return bundleIdentifier ?? "window.list.untitled".localized
    }
}
