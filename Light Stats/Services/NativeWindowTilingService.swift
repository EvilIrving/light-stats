//
//  NativeWindowTilingService.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import AppKit
import ApplicationServices
import OSLog

/// The window tiling commands macOS injects into every app's Window menu.
///
/// They are the system's own implementation: same target frames, same animation, same per-display
/// visible-area rules. Reusing them is the only way to stay aligned with what the green zoom button
/// and the system shortcuts do.
nonisolated enum NativeTilingCommand: Sendable, CaseIterable {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case fill
    case center
    case untile

    /// The menu item's `AXIdentifier`, which is the AppKit selector the item invokes. These are
    /// private selectors, so we never link them — we find the item macOS already built and press it.
    var accessibilityIdentifier: String {
        switch self {
        case .left: return "_zoomLeft:"
        case .right: return "_zoomRight:"
        case .top: return "_zoomTop:"
        case .bottom: return "_zoomBottom:"
        case .topLeft: return "_zoomTopLeft:"
        case .topRight: return "_zoomTopRight:"
        case .bottomLeft: return "_zoomBottomLeft:"
        case .bottomRight: return "_zoomBottomRight:"
        case .fill: return "_zoomFill:"
        case .center: return "_zoomCenter:"
        case .untile: return "_zoomUntile:"
        }
    }

    /// The native command for a snap action, or `nil` when macOS has no equivalent and the engine
    /// has to place the window itself (thirds, display moves, minimize).
    ///
    /// The system's arrangement presets (its "Fill & Arrange" layouts) are deliberately absent:
    /// they live in the system's own menu tree, and duplicating them here would only add paths to
    /// the same result instead of taking them away.
    static func matching(_ action: WindowSnapAction) -> NativeTilingCommand? {
        switch action {
        case .leftHalf: return .left
        case .rightHalf: return .right
        case .topHalf: return .top
        case .bottomHalf: return .bottom
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        case .maximize: return .fill
        case .center: return .center
        case .restore: return .untile
        case .leftThird, .leftTwoThirds, .centerThird, .rightTwoThirds, .rightThird,
             .nextDisplay, .previousDisplay, .minimize, .closeWindow, .quitApplication:
            return nil
        }
    }
}

/// Finds and presses the Window-menu items macOS injects into a running app.
///
/// Native tiling acts on the app's own key window, so the app has to be frontmost: AX reports
/// success for a press on an inactive app and then does nothing at all. That silent no-op is why
/// `isActive` gates every press and why callers still verify the window moved.
nonisolated final class NativeWindowTilingService: @unchecked Sendable {

    private let logger = AppLogger(category: "NativeWindowTiling")
    private let stateLock = NSLock()
    private var itemsByProcess: [pid_t: [String: AXUIElement]] = [:]

    /// Whether the app is frontmost. Nothing native can be driven otherwise.
    func isActive(_ processID: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: processID)?.isActive == true
    }

    /// Brings an app forward and waits briefly for the activation to land.
    ///
    /// The menu bar icon needs this: opening our own status item menu already took frontmost status
    /// away from the app the user was working in, while the native tiling item still has to act on
    /// that app's key window.
    func activate(_ processID: pid_t, timeout: TimeInterval = 0.2) -> Bool {
        if isActive(processID) { return true }
        guard let application = NSRunningApplication(processIdentifier: processID) else { return false }

        _ = application.activate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isActive(processID) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return isActive(processID)
    }

    /// Whether the app exposes the item for `command`. Resolving walks the app's Window menu once
    /// and caches every tiling item in it, so repeated menu validation stays a dictionary lookup.
    func supports(_ command: NativeTilingCommand, processID: pid_t) -> Bool {
        items(for: processID)[command.accessibilityIdentifier] != nil
    }

    /// Presses the system's own tiling item. A `true` result only means AX accepted the press —
    /// a disabled item accepts it too — so the caller confirms the window actually moved.
    func perform(_ command: NativeTilingCommand, processID: pid_t) -> Bool {
        guard isActive(processID) else {
            logger.debug("Native tiling skipped: app \(processID) is not frontmost")
            return false
        }
        guard let item = items(for: processID)[command.accessibilityIdentifier] else {
            logger.debug("Native tiling item \(command.accessibilityIdentifier) is unavailable")
            return false
        }

        let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
        guard result == .success else {
            logger.debug("Native tiling press failed: \(result.rawValue)")
            invalidate(processID: processID)
            return false
        }
        return true
    }

    /// Drops cached items. Called when a press fails, because a rebuilt menu invalidates the
    /// elements captured from the old one.
    func invalidate(processID: pid_t) {
        stateLock.lock()
        itemsByProcess[processID] = nil
        stateLock.unlock()
    }

    // MARK: - Menu lookup

    private func items(for processID: pid_t) -> [String: AXUIElement] {
        stateLock.lock()
        let cached = itemsByProcess[processID]
        stateLock.unlock()
        if let cached { return cached }

        let resolved = resolveItems(processID: processID)
        stateLock.lock()
        itemsByProcess[processID] = resolved
        stateLock.unlock()
        return resolved
    }

    private func resolveItems(processID: pid_t) -> [String: AXUIElement] {
        guard let menu = windowMenu(processID: processID) else { return [:] }
        var found: [String: AXUIElement] = [:]
        collect(from: menu, depth: 0, into: &found)
        return found
    }

    /// The Window menu is found by content rather than by title: it is the only menu bar menu that
    /// holds the system's tiling items, and matching a localized title would be fragile.
    private func windowMenu(processID: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processID)
        guard let menuBar: AXUIElement = copyAttribute(kAXMenuBarAttribute, from: application) else { return nil }

        let barItems: [AXUIElement] = copyAttribute(kAXChildrenAttribute, from: menuBar) ?? []
        for barItem in barItems {
            let menus: [AXUIElement] = copyAttribute(kAXChildrenAttribute, from: barItem) ?? []
            for menu in menus {
                let menuItems: [AXUIElement] = copyAttribute(kAXChildrenAttribute, from: menu) ?? []
                if menuItems.contains(where: isTilingItem) {
                    return menu
                }
            }
        }
        return nil
    }

    private func isTilingItem(_ element: AXUIElement) -> Bool {
        guard let identifier: String = copyAttribute("AXIdentifier", from: element) else { return false }
        return identifier.hasPrefix(tilingIdentifierPrefix)
    }

    /// Tiling items sit at most three levels below the menu: item → submenu → item. The submenu
    /// contents are readable without ever opening the menu.
    private func collect(from element: AXUIElement, depth: Int, into found: inout [String: AXUIElement]) {
        guard depth <= 3 else { return }
        let children: [AXUIElement] = copyAttribute(kAXChildrenAttribute, from: element) ?? []
        for child in children {
            if let identifier: String = copyAttribute("AXIdentifier", from: child),
               identifier.hasPrefix(tilingIdentifierPrefix) {
                found[identifier] = child
            }
            collect(from: child, depth: depth + 1, into: &found)
        }
    }

    private var tilingIdentifierPrefix: String { "_zoom" }

    private func copyAttribute<T>(_ attribute: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
