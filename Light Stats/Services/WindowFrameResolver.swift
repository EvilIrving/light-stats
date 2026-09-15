//
//  WindowFrameResolver.swift
//  Light Stats
//

import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

/// A frame plus the path that produced it, for diagnostics.
nonisolated struct ResolvedWindowFrame: Hashable, Sendable {
    var frame: CGRect
    /// Stable path label: `ax`, `ax-window`, `window-server`, `window-list`.
    var source: String
}

/// Reads a window's frame with fallbacks.
///
/// One path is not enough, and this is the single most important piece of plumbing in the
/// subsystem. Wins keeps four (`dragWindowRectAX → AXFallback → WindowServer → WindowListFallback`)
/// because the failure modes differ by app: Electron windows report a usable frame on the element
/// but not on their children; Java and some games report nothing until `AXEnhancedUserInterface`
/// is on; and a window that is mid-animation reports a stale frame on every path. Giving up quietly
/// is not an option — a snap that cannot read the frame silently does nothing, which is exactly the
/// "it just doesn't work sometimes" complaint.
///
/// All frames are in Accessibility space. `CGWindowBounds` is already top-left based, so it needs no
/// flip; only `NSScreen` values do, and that conversion lives in `WindowSnappingService`.
nonisolated enum WindowFrameResolver {

    private static let logger = AppLogger(category: "WindowFrame")

    static func frame(
        of element: AXUIElement,
        hint: CGRect? = nil,
        title: String? = nil
    ) -> ResolvedWindowFrame? {
        AXCommandQueue.shared.sync { resolve(of: element, hint: hint, title: title) }
    }

    private static func resolve(
        of element: AXUIElement,
        hint: CGRect?,
        title: String?
    ) -> ResolvedWindowFrame? {
        if let frame = frameFromAttributes(of: element) {
            return ResolvedWindowFrame(frame: frame, source: "ax")
        }
        if let window = nearestWindowElement(from: element),
           !CFEqual(window, element),
           let frame = frameFromAttributes(of: window) {
            return ResolvedWindowFrame(frame: frame, source: "ax-window")
        }
        if let frame = frameFromWindowServer(of: element) {
            return ResolvedWindowFrame(frame: frame, source: "window-server")
        }
        if let frame = frameFromWindowList(element: element, hint: hint, title: title) {
            return ResolvedWindowFrame(frame: frame, source: "window-list")
        }
        logger.debug("No frame path resolved for element")
        return nil
    }

    /// Position + size as the app itself reports them. Not queued: the queued `frame(of:)` is the
    /// entry point, and this is the primitive it and the placement engine both use.
    static func frameFromAttributes(of element: AXUIElement) -> CGRect? {
        AXElementReader.frame(of: element)
    }

    /// Whether an element will accept a write to its frame.
    static func isSettable(_ element: AXUIElement) -> Bool {
        AXCommandQueue.shared.sync {
            AXElementReader.isSettable(kAXPositionAttribute, of: element)
                || AXElementReader.isSettable(kAXSizeAttribute, of: element)
        }
    }

    /// The window's `CGWindowID`, when it exposes one. Most apps return 0, which is why every
    /// caller has to have a next step.
    static func windowNumber(of element: AXUIElement) -> CGWindowID? {
        AXCommandQueue.shared.sync {
            let number: Int? = AXElementReader.attribute(windowNumberAttribute, from: element)
            guard let number, number > 0 else { return nil }
            return CGWindowID(number)
        }
    }

    // MARK: - Fallbacks

    private static func nearestWindowElement(from element: AXUIElement) -> AXUIElement? {
        if let window: AXUIElement = AXElementReader.attribute(kAXWindowAttribute, from: element) {
            return window
        }
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else { return nil }
            let role: String? = AXElementReader.attribute(kAXRoleAttribute, from: candidate)
            if role == kAXWindowRole as String { return candidate }
            current = AXElementReader.attribute(kAXParentAttribute, from: candidate)
        }
        return nil
    }

    /// WindowServer lookup by window id. Cheapest and most precise when the id is available.
    private static func frameFromWindowServer(of element: AXUIElement) -> CGRect? {
        guard let windowID = windowNumber(of: element) else { return nil }
        guard let info = WindowServerInventory.info(for: windowID) else { return nil }
        return usable(info.bounds)
    }

    /// Last resort: match a window by owner pid, guided by the title and by where the window is
    /// believed to be. Without a hint this would happily return a different window of the same app.
    private static func frameFromWindowList(element: AXUIElement, hint: CGRect?, title: String?) -> CGRect? {
        guard let processID = AXElementReader.processIdentifier(of: element) else { return nil }
        guard let entry = WindowServerInventory.bestMatch(
            processID: processID,
            title: title,
            hint: hint,
            excluding: windowNumber(of: element)
        ) else {
            return nil
        }
        return usable(entry.bounds)
    }

    /// Guards against a window reporting absurd bounds while it is being created or torn down.
    private static func usable(_ rect: CGRect) -> CGRect? {
        guard rect.width > 1, rect.height > 1 else { return nil }
        guard rect.width < 100_000, rect.height < 100_000 else { return nil }
        return rect
    }

    /// Whether Accessibility has been asked to expose enhanced (Electron / Java) window trees.
    ///
    /// Without this flag the AX tree of an Electron or Java app is nearly empty, which is the most
    /// likely reason a titlebar gesture used to miss on those windows. Setting it is a property of
    /// the *target* application, so it has to be applied per app, lazily, once.
    static func enableEnhancedUserInterface(for processID: pid_t) {
        let application = AXUIElementCreateApplication(processID)
        let result = AXUIElementSetAttributeValue(
            application,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
        if result != .success {
            logger.debug("AXEnhancedUserInterface refused for \(processID): \(result.rawValue)")
        }
    }

    private static var windowNumberAttribute: String { "AXWindowNumber" }
}
