//
//  WindowPreviewCatalog.swift
//  Light Stats
//

import AppKit
import ApplicationServices

/// Enumerating previews performs no cross-process Accessibility calls.
nonisolated enum WindowPreviewCatalog {
    static func groups(exclusions: Set<String>, processID: pid_t? = nil) -> [ApplicationWindowGroup] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPID
                && (processID == nil || $0.processIdentifier == processID)
                && !exclusions.contains($0.bundleIdentifier ?? "")
        }
        let windows = Dictionary(grouping: WindowServerInventory.allWindows().filter(isPreviewable), by: \.processID)
        return applications.compactMap { app in
            let entries = windows[app.processIdentifier] ?? []
            guard !entries.isEmpty else { return nil }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            let items = entries.map { entry in
                WindowPreviewItem(
                    id: "\(entry.processID)-win-\(entry.windowID)",
                    title: entry.title.flatMap { $0.isEmpty ? nil : $0 } ?? app.localizedName ?? "",
                    isMinimized: false, isOnScreen: entry.isOnScreen, frame: entry.bounds,
                    element: element, processID: entry.processID, appName: app.localizedName ?? "",
                    bundleIdentifier: app.bundleIdentifier, windowID: entry.windowID, needsElementResolution: true
                )
            }
            return ApplicationWindowGroup(processID: app.processIdentifier, appName: app.localizedName ?? "",
                                          bundleIdentifier: app.bundleIdentifier, windows: items)
        }
    }

    static func isPreviewable(_ entry: WindowServerInventory.Entry) -> Bool {
        entry.layer == 0 && entry.bounds.width >= 80 && entry.bounds.height >= 60
            && !(entry.title?.lowercased().contains("modalwebviewwidget") ?? false)
    }
}
