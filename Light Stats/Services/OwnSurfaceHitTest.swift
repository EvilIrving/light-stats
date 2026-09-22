//
//  OwnSurfaceHitTest.swift
//  Light Stats
//

import CoreGraphics
import Darwin
import Foundation

/// Answers the one question an Accessibility hit test must not ask: is this point ours?
///
/// `AXUIElementCopyElementAtPosition` short-circuits a request whose answer lives in the calling
/// process. Instead of sending it to that application's main run loop, the Accessibility server runs
/// the application's own AppKit hit test **on the calling thread**. AppKit's Accessibility entry
/// points are main-thread-only — `NSAccessibilityIsSelectorUsingBaseImplementation` mutates a shared
/// selector cache — so the same call from `AXCommandQueue` traps inside CoreFoundation.
///
/// Measured on this machine: `WindowDragMonitorService.resolveWindow(at:)` asking about our own
/// status item and about our own popover both crashed the app in
/// `NSAccessibilityIsSelectorUsingBaseImplementation` (2026-09-16 01:47, 2026-09-17 00:35 and
/// 00:40), the last two while the popover was on screen. Both surfaces are returned by the
/// Accessibility hit test as *our* process, and the drag pipeline already refuses to act on our own
/// windows — so skipping the call costs the feature nothing and removes the crash.
nonisolated enum OwnSurfaceHitTest {

    /// Whether asking Accessibility about this point would land on one of our own surfaces.
    static func wouldResolveOwnUI(at point: CGPoint, processID: pid_t = getpid()) -> Bool {
        if let screen = ScreenGeometryProvider.screen(containing: point), isInMenuBarBand(point, screen: screen) {
            return true
        }
        return isOwnWindowOnTop(at: point, in: WindowServerInventory.onScreenWindows(), processID: processID)
    }

    /// The strip the menu bar occupies, where every status item lives — including the ones this app
    /// owns. `visibleFrame` is the same top boundary the island uses, and it is the only part of the
    /// screen no draggable window can occupy.
    static func isInMenuBarBand(_ point: CGPoint, screen: SnapScreenGeometry) -> Bool {
        point.y >= screen.frame.minY && point.y < screen.visibleFrame.minY
    }

    /// Whether the frontmost window at the point belongs to us.
    ///
    /// The WindowServer list is front-to-back, so the first window containing the point is the one a
    /// hit test would have resolved. A fully transparent window is not hit-testable and must not
    /// block a resolve for whatever is behind it.
    static func isOwnWindowOnTop(
        at point: CGPoint,
        in windows: [WindowServerInventory.Entry],
        processID: pid_t
    ) -> Bool {
        guard let topmost = windows.first(where: { $0.alpha > 0 && $0.bounds.contains(point) }) else {
            return false
        }
        return topmost.processID == processID
    }
}
