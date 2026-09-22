//
//  SnapGridGeometry.swift
//  Light Stats
//

import CoreGraphics

/// Turns normalized layout data into screen rectangles.
///
/// One function covers every layout the product ships or the user can build. Arrangement families,
/// thirds, quadrants, and anything the grid selector produces are all the same expression — a
/// normalized rect plus a gap rule, with boundaries far easier to test than a type per arrangement.
nonisolated enum SnapGridGeometry {

    /// Edge-matching tolerance in points. Rects derived from the same bounds land on the boundary
    /// exactly, but a caller may hand in a value that has been through a float round-trip.
    private static let boundaryTolerance: CGFloat = 0.5

    /// `bounds` after the outer margin. Never produces a negative size, so margins larger than the
    /// screen degrade to a zero-area rect instead of an inverted one.
    static func insetBounds(_ bounds: CGRect, margins: SnapMargins) -> CGRect {
        let inset = bounds.insetBy(dx: margins.outer, dy: margins.outer)
        guard inset.width > 0, inset.height > 0 else {
            return CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        }
        return inset
    }

    /// Screen rect of one normalized tile, in three steps: inset the whole area by the outer
    /// margin, place the tile inside what is left, then split the inner gap on whichever of its
    /// edges are interior.
    ///
    /// Doing the outer inset *first* is what makes two neighbouring tiles exactly `margins.inner`
    /// apart and makes a thirds layout divide the usable area evenly — instead of dividing the full
    /// screen and then shaving margins off each piece, which leaves the outer tiles visibly thinner
    /// than the inner one.
    static func frame(for rect: SnapNormalizedRect, in bounds: CGRect, margins: SnapMargins) -> CGRect {
        let area = insetBounds(bounds, margins: margins)
        let placed = CGRect(
            x: area.minX + CGFloat(rect.x) * area.width,
            y: area.minY + CGFloat(rect.y) * area.height,
            width: CGFloat(rect.width) * area.width,
            height: CGFloat(rect.height) * area.height
        )
        return applyingInnerGap(to: placed, in: area, inner: margins.inner)
    }

    static func frames(for layout: SnapLayout, in bounds: CGRect, margins: SnapMargins) -> [CGRect] {
        layout.segments.map { frame(for: $0.rect, in: bounds, margins: margins) }
    }

    /// Screen rect of any target. Regions go through the normalized path; the fixed actions go
    /// through `WindowSnapGeometry`, which derives the same gaps from the action's own rect.
    static func frame(for target: SnapTarget, in bounds: CGRect, margins: SnapMargins) -> CGRect? {
        switch target {
        case .region(let rect):
            return frame(for: rect, in: bounds, margins: margins)
        case .action(let action):
            return WindowSnapGeometry.regionFrame(for: action, bounds: bounds, margins: margins)
        case .visibility:
            return nil
        }
    }

    /// Splits the inner gap across a rect's interior edges.
    ///
    /// An edge lying on the boundary of `area` is the screen's own edge and gets nothing; an
    /// interior edge gives up half the gap. The comparison is by coordinates rather than by
    /// normalized fractions, so the fixed actions — whose geometry is computed as halves and thirds
    /// — and the normalized layout path go through exactly the same rule.
    static func applyingInnerGap(to rect: CGRect, in area: CGRect, inner: CGFloat) -> CGRect {
        guard inner > 0 else { return nonNegative(rect) }
        var adjusted = rect
        let half = inner / 2

        if abs(rect.minX - area.minX) > boundaryTolerance {
            adjusted.origin.x += half
            adjusted.size.width -= half
        }
        if abs(rect.maxX - area.maxX) > boundaryTolerance {
            adjusted.size.width -= half
        }
        if abs(rect.minY - area.minY) > boundaryTolerance {
            adjusted.origin.y += half
            adjusted.size.height -= half
        }
        if abs(rect.maxY - area.maxY) > boundaryTolerance {
            adjusted.size.height -= half
        }
        return nonNegative(adjusted)
    }

    private static func nonNegative(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, 0), height: max(rect.height, 0))
    }
}
