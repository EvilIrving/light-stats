//
//  WindowPreviewCatalog.swift
//  Light Stats
//

import AppKit
import ApplicationServices

/// The window list every preview surface shows — the Dock hover preview, the ⌘Tab switcher, and the
/// menu bar's window list before them.
///
/// Accessibility decides which windows exist and `WindowPreviewMerge` adds the ones it cannot see;
/// see that type for why both layers are needed. This type only walks the running applications and
/// puts the two together.
nonisolated enum WindowPreviewCatalog {

    static func groups(exclusions: Set<String>, processID: pid_t? = nil) -> [ApplicationWindowGroup] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPID
                && (processID == nil || $0.processIdentifier == processID)
                && !exclusions.contains($0.bundleIdentifier ?? "")
        }
        // One WindowServer snapshot for every application: it is a full enumeration of the system
        // and costs more than all of the Accessibility reads it is joined to.
        let serverWindows = Dictionary(
            grouping: WindowServerInventory.allWindows().filter(isPreviewable),
            by: \.processID
        )
        return applications.compactMap { app in
            let entries = serverWindows[app.processIdentifier] ?? []
            let accessibility = WindowListService.windows(
                forApplication: app.processIdentifier,
                userExclusions: exclusions,
                serverWindows: entries
            )
            let items = WindowPreviewMerge.items(
                accessibility: accessibility,
                serverWindows: entries,
                application: WindowPreviewMerge.Application(
                    processID: app.processIdentifier,
                    appName: app.localizedName ?? "",
                    bundleIdentifier: app.bundleIdentifier,
                    element: AXUIElementCreateApplication(app.processIdentifier)
                )
            )
            guard !items.isEmpty else { return nil }
            return ApplicationWindowGroup(
                processID: app.processIdentifier,
                appName: app.localizedName ?? "",
                bundleIdentifier: app.bundleIdentifier,
                windows: items
            )
        }
    }

    /// The coarsest filter, applied to the WindowServer's own list: a real window of a plausible
    /// size, at the normal window layer, that is not fully transparent.
    static func isPreviewable(_ entry: WindowServerInventory.Entry) -> Bool {
        entry.layer == 0 && entry.alpha > 0
            && entry.bounds.width >= 80 && entry.bounds.height >= 60
            && !(entry.title?.lowercased().contains("modalwebviewwidget") ?? false)
    }
}
