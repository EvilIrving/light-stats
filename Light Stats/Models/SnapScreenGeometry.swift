//
//  SnapScreenGeometry.swift
//  Light Stats
//

import CoreGraphics

/// One display, expressed in Accessibility space.
///
/// `frame` is the whole display and `visibleFrame` excludes the menu bar and the Dock. Both are
/// flipped out of Cocoa once, at the service boundary, so every policy below is written against a
/// single coordinate system and never has to know about the flip.
struct SnapScreenGeometry: Sendable, Hashable {

    var frame: CGRect
    var visibleFrame: CGRect

    /// Display index in the engine's own top-to-bottom, left-to-right ordering.
    var index: Int

    init(frame: CGRect, visibleFrame: CGRect, index: Int = 0) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.index = index
    }

    func contains(_ point: CGPoint) -> Bool {
        frame.contains(point)
    }

    /// Boundaries a drag is measured against.
    ///
    /// Left, right, and bottom use the physical display: the pointer is allowed into the Dock and
    /// off the outside edges, and the window follows as far as the system permits. The top uses the
    /// **visible** area instead, because that is the line a window can actually be pushed against —
    /// measuring the top against the physical edge would mean the user has to put the pointer into
    /// the menu bar for the island to arm.
    var dragBoundaries: (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        (left: frame.minX, right: frame.maxX, top: visibleFrame.minY, bottom: frame.maxY)
    }

    /// Signed distance from a point to each drag boundary. Positive means inside.
    func edgeDistances(to point: CGPoint) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let boundaries = dragBoundaries
        return (
            left: point.x - boundaries.left,
            right: boundaries.right - point.x,
            top: point.y - boundaries.top,
            bottom: boundaries.bottom - point.y
        )
    }
}
