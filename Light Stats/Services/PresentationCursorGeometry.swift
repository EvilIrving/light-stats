//
//  PresentationCursorGeometry.swift
//  Light Stats
//
//  Placement math for the presentation cursor: pack cell pixels → rendered points,
//  and the overlay window origin that puts the arrow tip exactly on the pointer.
//

import CoreGraphics

nonisolated enum PresentationCursorGeometry {
    /// Rendered size of one atlas cell. 128px of art on 64pt keeps a 2× Retina
    /// display pixel-exact and makes the arrow about twice a system cursor.
    static let renderSize: CGFloat = 64

    /// Arrow tip inside the rendered square, in points from its top-left corner.
    static func hotspot(
        cellHotspot: CGPoint,
        cellPixels: Int = PresentationCursorAtlas.cellPixels,
        renderSize: CGFloat = PresentationCursorGeometry.renderSize
    ) -> CGPoint {
        guard cellPixels > 0, renderSize > 0 else { return .zero }
        let scale = renderSize / CGFloat(cellPixels)
        return CGPoint(x: cellHotspot.x * scale, y: cellHotspot.y * scale)
    }

    /// Origin (bottom-left corner, Cocoa screen coordinates as reported by
    /// `NSEvent.mouseLocation`, y up) of the overlay window that puts its arrow tip on
    /// `pointer`. The hotspot is measured downward from the image top, hence the
    /// `renderSize - hotspot.y` flip.
    static func windowOrigin(
        pointer: CGPoint,
        hotspot: CGPoint,
        renderSize: CGFloat = PresentationCursorGeometry.renderSize
    ) -> CGPoint {
        CGPoint(
            x: pointer.x - hotspot.x,
            y: pointer.y - renderSize + hotspot.y
        )
    }
}
