//
//  WindowPreviewMerge.swift
//  Light Stats
//

import ApplicationServices
import CoreGraphics

/// Which windows an application's preview shows.
///
/// Accessibility is the layer that can tell a real window from the WindowServer's furniture, and it
/// is measured rather than assumed: on this machine WeChat publishes nine layer-0 windows to the
/// WindowServer and one to Accessibility, Chrome nine against two, Fork six against one, and nearly
/// every AppKit application carries an untitled 500×500 window at the bottom-left of the screen
/// that no user has ever seen. So the Accessibility window list comes first, and
/// `WindowListService` has already filtered it through the same three-layer
/// `SnapWindowEligibility` every other surface uses.
///
/// Accessibility is not complete either. Tencent's clients and Swing applications publish a partial
/// list — WeChat's own main window is missing from it entirely — and an application whose
/// Accessibility is unavailable is missing from it altogether. So the WindowServer entries are
/// *added*, never substituted, and only on three conditions:
///
/// 1. the window names itself. An untitled layer-0 window is indistinguishable from a shadow, a
///    full-width screen strip, or an offscreen render surface, and every one of those is in the
///    WindowServer's list for some application on this machine;
/// 2. Accessibility does not already account for it, by window number or by title;
/// 3. the user can actually reach it — it is on screen, or it is a hidden window tab (see below).
nonisolated enum WindowPreviewMerge {

    struct Application {
        var processID: pid_t
        var appName: String
        var bundleIdentifier: String?
        /// The application element, which is what a WindowServer-only item resolves against when
        /// the user acts on it.
        var element: AXUIElement
    }

    static func items(
        accessibility: [WindowPreviewItem],
        serverWindows: [WindowServerInventory.Entry],
        application: Application
    ) -> [WindowPreviewItem] {
        let accountedWindowIDs = Set(accessibility.compactMap(\.windowID))
        let accountedTitles = Set(accessibility.map(\.title))
        let accountedFrames = accessibility.compactMap(\.frame)

        var supplements: [WindowPreviewItem] = []
        var indexByTitle: [String: Int] = [:]

        for entry in serverWindows {
            guard let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                continue
            }
            if accountedWindowIDs.contains(entry.windowID) { continue }
            if accountedTitles.contains(title) { continue }
            guard entry.isOnScreen || isHiddenWindowTab(entry.bounds, siblings: accountedFrames) else {
                continue
            }

            let item = WindowPreviewItem(
                id: WindowPreviewItem.identifier(
                    processID: application.processID,
                    windowID: entry.windowID,
                    element: application.element
                ),
                title: title,
                isMinimized: false,
                isOnScreen: entry.isOnScreen,
                frame: entry.bounds,
                element: application.element,
                processID: application.processID,
                appName: application.appName,
                bundleIdentifier: application.bundleIdentifier,
                windowID: entry.windowID,
                needsElementResolution: true
            )

            guard let existing = indexByTitle[title] else {
                indexByTitle[title] = supplements.count
                supplements.append(item)
                continue
            }
            // Two WindowServer windows can carry the same title and only one of them is the window
            // the user means: WeChat publishes its main window twice — 1042×760 and 280×380 — with
            // nothing in the WindowServer list to say which is which. The larger one is the window.
            if area(supplements[existing].frame) >= area(item.frame) { continue }
            supplements[existing] = item
        }

        // One card per window. An application can report the same window twice — Accessibility may
        // publish a window and the sheet drawn inside it as two elements that resolve to one
        // WindowServer window — and a list with a repeated identity is the duplicate card a user
        // reads as a bug.
        var seen = Set<String>()
        return (accessibility + supplements).filter { seen.insert($0.id).inserted }
    }

    /// A window the user can reach is one of two things, and the WindowServer says which.
    ///
    /// **On screen** is the ordinary case: the tencent clients and Swing applications have windows
    /// the user is looking at that Accessibility does not name, which is the whole reason this merge
    /// exists. A window that is neither on screen nor in Accessibility is not something the user is
    /// looking at, and a card for it can only ever activate the application.
    ///
    /// **A hidden window tab** is the one off-screen window that is reachable, and it is offered
    /// through the application's own tab buttons (`WindowListService.reveal` presses the matching
    /// one). Every tab of a natively tabbed window reports the frame of the tab that happens to be
    /// showing, so sharing a rectangle with a window Accessibility *does* list is what identifies
    /// one — Fork's other repositories are exactly this.
    ///
    /// Everything else is furniture an application built and never showed. Measured: IINA
    /// pre-creates a 600×432 window per installed plugin at launch (`io.iina.opensub`,
    /// `io.iina.user-script` — the plugin preference pages), leaves them ordered out for the life of
    /// the process, and never names them to Accessibility, so a freshly opened IINA offered a Dock
    /// preview of three windows for the one it had.
    private static func isHiddenWindowTab(_ bounds: CGRect, siblings: [CGRect]) -> Bool {
        siblings.contains { candidate in
            abs(candidate.minX - bounds.minX) <= 1 && abs(candidate.minY - bounds.minY) <= 1
                && abs(candidate.width - bounds.width) <= 1 && abs(candidate.height - bounds.height) <= 1
        }
    }

    private static func area(_ rect: CGRect?) -> CGFloat {
        guard let rect else { return 0 }
        return rect.width * rect.height
    }
}
