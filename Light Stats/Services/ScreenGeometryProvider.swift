//
//  ScreenGeometryProvider.swift
//  Light Stats
//

import AppKit
import CoreGraphics

/// The one place that converts between Cocoa and Accessibility coordinates.
///
/// Accessibility puts the origin at the primary display's top-left with `y` growing downward;
/// Cocoa puts it at that display's bottom-left with `y` growing upward. Everything downstream —
/// policies, geometry, previews, the island — stays in Accessibility space, so the flip happens
/// here and nowhere else.
///
/// The reference height must be the **primary** display's `frame.maxY`, the one holding the menu
/// bar. Using the topmost display instead shifts every frame by the height of whatever sits above
/// the primary one, which is how snapping used to break the moment an external display was
/// arranged above the built-in screen.
nonisolated enum ScreenGeometryProvider {

    /// One display snapshot: the ordered Accessibility-space screens **and** the reference height
    /// they were built with.
    ///
    /// The two travel together because they have to agree. `referenceMaxY` is what every flip in the
    /// app is measured against, and it used to be derived twice, by different rules — a search for
    /// the display whose origin is `(0, 0)` in one place, `NSScreen.screens.first` in the other. Both
    /// give the same answer in a normal arrangement, but each is a separate assumption that has to
    /// stay true, and the search carried a `0` fallback that would mirror every rectangle in the app.
    struct Snapshot: Equatable, Sendable {
        var screens: [SnapScreenGeometry]
        /// The primary display's `frame.maxY` — the height Accessibility `y = 0` sits at.
        var referenceMaxY: CGFloat
    }

    /// Cached display snapshot.
    ///
    /// `NSScreen.screens` enumerates and sorts every display. The drag pipeline asks for the screen
    /// under the pointer on each pointer sample — up to sixty times a second — so re-enumerating
    /// each time would be work done purely to be thrown away. The cache is invalidated by
    /// `didChangeScreenParametersNotification`, which is the only thing that can change the answer.
    private final class ScreenCache: @unchecked Sendable {
        private let lock = NSLock()
        private var stamp: TimeInterval = -.infinity
        private var snapshot: Snapshot?
        private let ttl: TimeInterval = 2

        func current(_ compute: () -> Snapshot) -> Snapshot {
            lock.lock()
            let now = ProcessInfo.processInfo.systemUptime
            if let snapshot, now - stamp < ttl {
                lock.unlock()
                return snapshot
            }
            lock.unlock()

            let computed = compute()
            lock.lock()
            snapshot = computed
            stamp = ProcessInfo.processInfo.systemUptime
            lock.unlock()
            return computed
        }

        func invalidate() {
            lock.lock()
            stamp = -.infinity
            lock.unlock()
        }
    }

    private static let cache = ScreenCache()

    /// Called when the display configuration changes; the next read rebuilds the snapshot.
    static func invalidate() {
        cache.invalidate()
    }

    /// The one rule for the Accessibility ↔ Cocoa reference height: the **primary** display's
    /// `frame.maxY`, where the primary is the display `NSScreen.screens` lists first — the one
    /// holding the menu bar.
    ///
    /// Its origin is deliberately not consulted. Whether that display happens to sit at `(0, 0)` is
    /// not part of why it is the reference, and searching for that origin made the whole conversion
    /// depend on an arrangement detail that has nothing to do with the coordinate space.
    ///
    /// Pure, so the rule is pinned by tests without a display attached — including the no-display
    /// case, which used to yield a `0` reference and mirror every rectangle in the app.
    static func referenceMaxY(cocoaFrames: [CGRect]) -> CGFloat {
        cocoaFrames.first?.maxY ?? 0
    }

    static func flipReferenceMaxY() -> CGFloat {
        cachedSnapshot().referenceMaxY
    }

    /// Every display, ordered top-to-bottom then left-to-right in Accessibility space, so "next
    /// display" means the same thing on a vertical stack as on a horizontal row.
    ///
    /// Pure: it takes the Cocoa rectangles, so the ordering, the flip, and the resulting geometry can
    /// be tested against an arrangement no test machine has — a display above the primary, one at
    /// negative x, an ultrawide beside a 1080p — instead of only against whatever is plugged in.
    static func snapshot(cocoaFrames: [(frame: CGRect, visibleFrame: CGRect)]) -> Snapshot {
        let reference = referenceMaxY(cocoaFrames: cocoaFrames.map(\.frame))
        let ordered = cocoaFrames.sorted { lhs, rhs in
            let left = WindowSnapGeometry.flip(lhs.frame, aboutMaxY: reference)
            let right = WindowSnapGeometry.flip(rhs.frame, aboutMaxY: reference)
            if abs(left.minY - right.minY) > 1 { return left.minY < right.minY }
            return left.minX < right.minX
        }
        return Snapshot(
            screens: ordered.enumerated().map { index, screen in
                SnapScreenGeometry(
                    frame: WindowSnapGeometry.flip(screen.frame, aboutMaxY: reference),
                    visibleFrame: WindowSnapGeometry.flip(screen.visibleFrame, aboutMaxY: reference),
                    index: index
                )
            },
            referenceMaxY: reference
        )
    }

    /// The AppKit-backed snapshot, cached for the drag pipeline's per-sample reads.
    static func cachedSnapshot() -> Snapshot {
        cache.current {
            snapshot(cocoaFrames: NSScreen.screens.map { ($0.frame, $0.visibleFrame) })
        }
    }

    /// Every display, newest snapshot. Used by everything on a hot path.
    static func cachedScreens() -> [SnapScreenGeometry] {
        cachedSnapshot().screens
    }

    /// The display whose visible area contains a point given in Accessibility space.
    static func screen(containing axPoint: CGPoint) -> SnapScreenGeometry? {
        let screens = cachedScreens()
        if let hit = screens.first(where: { $0.frame.contains(axPoint) }) { return hit }
        // A point in a gap between displays (or just outside one during a drag) belongs to the
        // nearest display rather than to nothing.
        return screens.min { distance($0.frame, axPoint) < distance($1.frame, axPoint) }
    }

    /// The display a window mostly sits on.
    ///
    /// A window straddling two displays has its centre on neither, so the one under the largest
    /// share of it wins — using the centre alone would flip the answer as the window crosses the
    /// midpoint.
    static func screen(containing axFrame: CGRect) -> SnapScreenGeometry? {
        let screens = cachedScreens()
        if let containing = screens.first(where: { $0.frame.contains(CGPoint(x: axFrame.midX, y: axFrame.midY)) }) {
            return containing
        }
        var best: SnapScreenGeometry?
        var bestArea: CGFloat = 0
        for screen in screens {
            let overlap = screen.frame.intersection(axFrame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best ?? screens.first
    }

    static func toAccessibility(_ rect: CGRect) -> CGRect {
        WindowSnapGeometry.flip(rect, aboutMaxY: flipReferenceMaxY())
    }

    static func toCocoa(_ rect: CGRect) -> CGRect {
        WindowSnapGeometry.flip(rect, aboutMaxY: flipReferenceMaxY())
    }

    /// Accessibility-space point from a Cocoa point, as `NSEvent.location` reports it.
    static func toAccessibility(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: flipReferenceMaxY() - point.y)
    }

    private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
