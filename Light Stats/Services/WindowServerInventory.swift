//
//  WindowServerInventory.swift
//  Light Stats
//

import AppKit
import CoreGraphics

/// Snapshot of the WindowServer's own window list.
///
/// `CGWindowListCopyWindowInfo` is the only inventory of windows reachable without Accessibility
/// and without any permission beyond what the app already has. It is the deepest layer of every
/// fallback chain in this subsystem, and it is also what lets the window list show a title and a
/// size for windows whose app refuses to answer AX queries.
nonisolated enum WindowServerInventory {

    nonisolated struct Entry: Hashable, Sendable {
        var windowID: CGWindowID
        var processID: pid_t
        var bounds: CGRect
        var title: String?
        var layer: Int
        var isOnScreen: Bool
        var ownerName: String?
    }

    /// Windows currently on screen, front-to-back.
    static func onScreenWindows() -> [Entry] {
        windows(options: [.optionOnScreenOnly, .excludeDesktopElements])
    }

    /// Every window, including off-screen ones, for the cases where a window is mid-move and has
    /// briefly left the display.
    static func allWindows() -> [Entry] {
        windows(options: [.optionAll, .excludeDesktopElements])
    }

    static func info(for windowID: CGWindowID) -> Entry? {
        onScreenWindows().first { $0.windowID == windowID }
            ?? allWindows().first { $0.windowID == windowID }
    }

    /// Normal-layer windows of one process, front-to-back.
    ///
    /// Only layer 0 is considered: a title bar, a shadow, and a tooltip all belong to the same
    /// process, and picking one of those would place the wrong rectangle.
    static func windows(of processID: pid_t) -> [Entry] {
        allWindows().filter { $0.processID == processID && $0.layer == 0 }
    }

    /// The window of `processID` that best matches the given hints.
    static func bestMatch(
        processID: pid_t,
        title: String?,
        hint: CGRect?,
        excluding excludedID: CGWindowID?
    ) -> Entry? {
        let candidates = allWindows().filter { entry in
            entry.processID == processID
                && entry.layer == 0
                && entry.windowID != excludedID
                && entry.bounds.width > 40
                && entry.bounds.height > 40
        }
        guard !candidates.isEmpty else { return nil }

        if let title, !title.isEmpty {
            let exact = candidates.filter { $0.title == title }
            if let best = pick(from: exact, hint: hint) { return best }
        }
        return pick(from: candidates, hint: hint)
    }

    private static func pick(from candidates: [Entry], hint: CGRect?) -> Entry? {
        guard let hint else {
            return candidates.max { area($0.bounds) < area($1.bounds) }
        }
        return candidates.max { overlap($0.bounds, hint) < overlap($1.bounds, hint) }
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private static func windows(options: CGWindowListOption) -> [Entry] {
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dictionary in
            guard let windowID = dictionary[kCGWindowNumber as String] as? CGWindowID,
                  let ownerPID = dictionary[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                return nil
            }
            return Entry(
                windowID: windowID,
                processID: ownerPID,
                bounds: bounds,
                title: dictionary[kCGWindowName as String] as? String,
                layer: dictionary[kCGWindowLayer as String] as? Int ?? 0,
                isOnScreen: (dictionary[kCGWindowIsOnscreen as String] as? Bool) ?? false,
                ownerName: dictionary[kCGWindowOwnerName as String] as? String
            )
        }
    }
}
