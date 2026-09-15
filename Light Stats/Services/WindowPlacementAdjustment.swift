//
//  WindowPlacementAdjustment.swift
//  Light Stats
//

import CoreGraphics

nonisolated enum WindowPlacementAdjustment {
    /// Keep the outer edges aligned when an app quantizes its size (terminals), and center fixed-size windows in their tile.
    static func frame(target: CGRect, acceptedSize: CGSize, screen: CGRect, isResizable: Bool) -> CGRect {
        var origin = target.origin
        if !isResizable {
            origin = CGPoint(x: target.midX - acceptedSize.width / 2, y: target.midY - acceptedSize.height / 2)
        } else {
            if target.midX > screen.midX { origin.x = target.maxX - acceptedSize.width }
            if target.midY > screen.midY { origin.y = target.maxY - acceptedSize.height }
        }
        origin.x = min(max(origin.x, screen.minX), max(screen.minX, screen.maxX - acceptedSize.width))
        origin.y = min(max(origin.y, screen.minY), max(screen.minY, screen.maxY - acceptedSize.height))
        return CGRect(origin: origin, size: acceptedSize)
    }
}
