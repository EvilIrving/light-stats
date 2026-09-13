//
//  PanelPointerPlacement.swift
//  Light Stats
//
//  Cocoa-space placement for a panel summoned at the pointer.
//

import Foundation

nonisolated enum PanelPointerPlacement {
    /// Places the panel so its top edge meets the pointer, centered horizontally,
    /// then clamps to `visibleFrame`. If the panel is larger than the visible area,
    /// it pins to the bottom-left of that frame.
    static func origin(size: CGSize, mouse: CGPoint, visibleFrame: CGRect) -> CGPoint {
        var x = mouse.x - (size.width / 2)
        var y = mouse.y - size.height

        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - size.width
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - size.height

        x = maxX >= minX ? min(max(x, minX), maxX) : minX
        y = maxY >= minY ? min(max(y, minY), maxY) : minY
        return CGPoint(x: x, y: y)
    }
}
