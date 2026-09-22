//
//  AppWindowPolicy.swift
//  Light Stats
//

import Foundation

/// Which of the app's own windows are windows a user would expect to find in ⌘Tab.
///
/// Light Stats is a menu-bar app (`LSUIElement`), so macOS gives it no Dock icon and no ⌘Tab entry.
/// That is correct for everything the app shows *while* it is a menu-bar citizen: the popover, the
/// island, the previews, the toast and the presentation cursor are all panels floating above the
/// normal window level. It is wrong for a real window — the Settings window is an ordinary titled
/// window, and macOS hides it from every system affordance only because the app claims to have no
/// windows at all.
///
/// So the activation policy follows this decision: `.regular` while at least one window passes,
/// `.accessory` again as soon as none does.
nonisolated enum AppWindowPolicy {

    /// One of the app's windows, reduced to the four facts that decide the question.
    ///
    /// Taken as a value rather than an `NSWindow` so the rule is testable without a window server.
    struct Window: Equatable {
        var isVisible: Bool
        /// In the Dock as a miniaturised window. Still the user's window, so it still counts.
        var isMiniaturized: Bool
        /// `NSWindow.Level.normal`. Every piece of menu-bar chrome the app draws sits above it.
        var isNormalLevel: Bool
        /// `NSPanel` — the popover, the island, the previews, the toast, and the system's own
        /// open/save panels, none of which should ever put the app in the Dock.
        var isPanel: Bool
        /// A window that can carry a title bar. The cleaning overlay is borderless and full screen.
        var isTitled: Bool

        /// On screen, or in the Dock as a thumbnail — a window the user has not finished with.
        var isPresent: Bool { isVisible || isMiniaturized }
    }

    static func requiresRegularActivation(_ windows: [Window]) -> Bool {
        windows.contains { $0.isPresent && $0.isNormalLevel && !$0.isPanel && $0.isTitled }
    }
}
