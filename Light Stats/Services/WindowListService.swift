//
//  WindowListService.swift
//  Light Stats
//

import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

/// Enumerates and controls the windows of a running application.
///
/// Windows come from Accessibility because that is what can actually be acted on — raise, minimize,
/// close, move. The WindowServer inventory is joined in only to learn each window's `CGWindowID`,
/// which is what the thumbnail service needs; without that join the previews could show a title but
/// never a picture.
///
/// No Screen Recording permission is needed for any of this. Thumbnails are the one thing that
/// needs it, and they are missing rather than fatal when it is absent.
nonisolated enum WindowListService {

    private static let logger = AppLogger(category: "WindowList")

    /// Windows of `processID`, in the order the preview surfaces show them: on-screen first, then
    /// top-to-bottom, left-to-right.
    static func windows(
        forApplication processID: pid_t,
        userExclusions: Set<String>,
        honorsRestrictedList: Bool
    ) -> [WindowPreviewItem] {
        AXCommandQueue.shared.sync {
            windowsOnQueue(forApplication: processID, userExclusions: userExclusions)
        }
    }

    private static func windowsOnQueue(forApplication processID: pid_t, userExclusions: Set<String>) -> [WindowPreviewItem] {
        let application = AXUIElementCreateApplication(processID)
        let elements = AXElementReader.elements(kAXWindowsAttribute, from: application)
        guard !elements.isEmpty else { return [] }

        let running = NSRunningApplication(processIdentifier: processID)
        let bundleIdentifier = running?.bundleIdentifier
        let appName = running?.localizedName ?? ""
        // One WindowServer snapshot for the whole app, not one per window.
        let serverWindows = WindowServerInventory.windows(of: processID)

        var items: [WindowPreviewItem] = []
        for element in elements {
            let isMinimized: Bool = AXElementReader.attribute(kAXMinimizedAttribute, from: element) ?? false
            let title: String = AXElementReader.attribute(kAXTitleAttribute, from: element) ?? ""
            let isFullScreen: Bool? = AXElementReader.attribute("AXFullScreen", from: element)

            let candidate = SnapWindowCandidate(
                role: AXElementReader.attribute(kAXRoleAttribute, from: element),
                subrole: AXElementReader.attribute(kAXSubroleAttribute, from: element),
                title: title,
                bundleIdentifier: bundleIdentifier,
                executableName: running?.executableURL?.lastPathComponent,
                frame: WindowFrameResolver.frame(of: element)?.frame,
                isMinimized: isMinimized,
                isFullScreen: isFullScreen == true
            )
            guard SnapWindowEligibility.isPreviewable(candidate, userExclusions: userExclusions) else {
                continue
            }

            let windowID = resolveWindowID(
                element: element,
                title: title,
                frame: candidate.frame,
                serverWindows: serverWindows
            )
            items.append(
                WindowPreviewItem(
                    id: WindowPreviewItem.identifier(processID: processID, windowID: windowID, element: element),
                    title: title.isEmpty ? (bundleIdentifier ?? "window.list.untitled".localized) : title,
                    isMinimized: isMinimized,
                    isOnScreen: !isMinimized,
                    frame: candidate.frame,
                    element: element,
                    processID: processID,
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    windowID: windowID
                )
            )
        }

        return items.sorted(by: ordering)
    }

    /// Every regular application that currently has windows worth previewing, frontmost first.
    static func windowGroups(userExclusions: Set<String>, honorsRestrictedList: Bool) -> [ApplicationWindowGroup] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }

        var groups: [ApplicationWindowGroup] = []
        for application in applications {
            let windows = windows(
                forApplication: application.processIdentifier,
                userExclusions: userExclusions,
                honorsRestrictedList: honorsRestrictedList
            )
            guard !windows.isEmpty else { continue }
            groups.append(
                ApplicationWindowGroup(
                    processID: application.processIdentifier,
                    appName: application.localizedName ?? "",
                    bundleIdentifier: application.bundleIdentifier,
                    windows: windows
                )
            )
        }
        return groups
    }

    // MARK: - Window identity

    /// The window's `CGWindowID`, or `nil` when it cannot be established.
    ///
    /// `AXWindowNumber` is the direct answer and most apps do not provide it, so the fallback is a
    /// geometry-and-title match against the WindowServer's own list. Returning `nil` is fine and
    /// expected: the window still appears, it just appears without a thumbnail.
    private static func resolveWindowID(
        element: AXUIElement,
        title: String,
        frame: CGRect?,
        serverWindows: [WindowServerInventory.Entry]
    ) -> CGWindowID? {
        if let direct = WindowFrameResolver.windowNumber(of: element) {
            return direct
        }
        guard !serverWindows.isEmpty else { return nil }

        if !title.isEmpty {
            let exact = serverWindows.filter { $0.title == title }
            if let match = bestMatch(in: exact, frame: frame) { return match.windowID }
        }
        return bestMatch(in: serverWindows, frame: frame)?.windowID
    }

    private static func bestMatch(
        in candidates: [WindowServerInventory.Entry],
        frame: CGRect?
    ) -> WindowServerInventory.Entry? {
        guard let frame else { return candidates.first }
        return candidates.min { lhs, rhs in
            distance(lhs.bounds, frame) < distance(rhs.bounds, frame)
        }
    }

    private static func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY) + abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }

    // MARK: - Ordering

    /// On-screen windows first, then by vertical position, then horizontal — the order macOS' own
    /// Window menu uses, so the list is where a user already expects to find things.
    private static func ordering(_ lhs: WindowPreviewItem, _ rhs: WindowPreviewItem) -> Bool {
        if lhs.isMinimized != rhs.isMinimized { return !lhs.isMinimized }
        let left = lhs.frame ?? .zero
        let right = rhs.frame ?? .zero
        if abs(left.minY - right.minY) > 1 { return left.minY < right.minY }
        return left.minX < right.minX
    }

    private static func resolved(_ item: WindowPreviewItem) -> WindowPreviewItem? {
        guard item.needsElementResolution else { return item }
        guard let windowID = item.windowID, let server = WindowServerInventory.info(for: windowID),
              server.processID == item.processID else { return nil }
        let application = AXUIElementCreateApplication(item.processID)
        AXUIElementSetMessagingTimeout(application, 0.12)
        let windows = AXElementReader.elements(kAXWindowsAttribute, from: application)
        let candidates = windows.map { element in
            AXUIElementSetMessagingTimeout(element, 0.08)
            return WindowPreviewMatchPolicy.Candidate(
                windowID: WindowFrameResolver.windowNumber(of: element),
                title: AXElementReader.attribute(kAXTitleAttribute, from: element),
                frame: WindowFrameResolver.frameFromAttributes(of: element)
            )
        }
        guard let index = WindowPreviewMatchPolicy.index(
            windowID: windowID, title: server.title, frame: server.bounds, candidates: candidates
        ) else { return nil }
        let element = windows[index]
        var resolved = item
        resolved.element = element
        resolved.needsElementResolution = false
        resolved.isMinimized = AXElementReader.attribute(kAXMinimizedAttribute, from: element) ?? false
        return resolved
    }

    // MARK: - Control

    /// Brings a window forward and gives it keyboard focus.
    ///
    /// `AXRaise` alone is not enough for a window of a background app: the application also has to
    /// be activated, or the raise happens behind whatever the user is actually looking at.
    @discardableResult
    static func focus(_ item: WindowPreviewItem) -> Bool {
        AXCommandQueue.shared.sync {
            guard let resolved = resolved(item) else { return false }
            return focusOnQueue(resolved)
        }
    }

    private static func focusOnQueue(_ item: WindowPreviewItem) -> Bool {
        var focused = false
        if AXUIElementSetAttributeValue(item.element, kAXMainAttribute as CFString, kCFBooleanTrue) == .success {
            focused = true
        }
        if AXUIElementPerformAction(item.element, kAXRaiseAction as CFString) == .success {
            focused = true
        }
        NSRunningApplication(processIdentifier: item.processID)?.activate()
        if !focused {
            logger.debug("Window refused both main and raise")
        }
        return focused
    }

    @discardableResult
    static func minimize(_ item: WindowPreviewItem) -> Bool {
        AXCommandQueue.shared.sync {
            guard let item = resolved(item) else { return false }
            return AXUIElementSetAttributeValue(item.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
        }
    }

    @discardableResult
    static func deminimize(_ item: WindowPreviewItem) -> Bool {
        AXCommandQueue.shared.sync {
            guard let item = resolved(item) else { return false }
            return AXUIElementSetAttributeValue(item.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
        }
    }

    /// Un-minimizes if needed, then focuses. What every preview surface does on a click.
    @discardableResult
    static func reveal(_ item: WindowPreviewItem) -> Bool {
        AXCommandQueue.shared.sync {
            guard let item = resolved(item) else { return false }
            if item.isMinimized { _ = deminimize(item) }
            return focusOnQueue(item)
        }
    }

    @discardableResult
    static func close(_ item: WindowPreviewItem) -> Bool {
        AXCommandQueue.shared.sync {
            guard let item = resolved(item) else { return false }
            return close(element: item.element)
        }
    }

    @discardableResult
    static func close(element: AXUIElement) -> Bool {
        AXCommandQueue.shared.sync { closeOnQueue(element) }
    }

    private static func closeOnQueue(_ element: AXUIElement) -> Bool {
        if let button: AXUIElement = AXElementReader.attribute(kAXCloseButtonAttribute, from: element),
           AXUIElementPerformAction(button, kAXPressAction as CFString) == .success { return true }
        // `AXClose` has no constant in the public headers and is not implemented by every app, so
        // it is spelled out and treated as the optimistic path. The close *button* is the reliable
        // fallback, and reaching for it is what makes this work on Electron windows.
        if AXUIElementPerformAction(element, "AXClose" as CFString) == .success {
            return true
        }
        for child in AXElementReader.elements(kAXChildrenAttribute, from: element) {
            let subrole: String? = AXElementReader.attribute(kAXSubroleAttribute, from: child)
            if subrole == "AXCloseButton" {
                return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
            }
        }
        return false
    }
}
