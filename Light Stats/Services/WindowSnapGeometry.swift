//
//  WindowSnapGeometry.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import CoreGraphics

/// Pure placement math for the window snap engine.
///
/// Every rect here lives in **Accessibility space**: origin at the top-left corner of the primary
/// display, `y` growing downward. That is what `AXPosition` and `AXSize` speak, and the whole snap
/// pipeline stays in it — converting once at the boundary is what keeps multi-display placement
/// honest, because flipping with the wrong reference height silently shifts every frame that lands
/// outside the primary display.
enum WindowSnapGeometry {

    /// Windows rarely end up on the exact requested rect (apps clamp their size, the system rounds
    /// to the backing scale), so placement checks compare with a tolerance rather than for equality.
    static let placementTolerance: CGFloat = 2

    /// Frame an action asks for, given the target screen's visible area.
    static func targetFrame(
        for action: WindowSnapAction,
        visibleFrame: CGRect,
        currentSize: CGSize
    ) -> CGRect {
        if action == .center {
            return centeredFrame(size: currentSize, in: visibleFrame)
        }
        if let frame = halfOrQuarterFrame(for: action, in: visibleFrame) {
            return frame
        }
        if let frame = thirdFrame(for: action, in: visibleFrame) {
            return frame
        }
        // Restore, minimize, and display moves preview as the whole visible area.
        return visibleFrame
    }

    private static func halfOrQuarterFrame(for action: WindowSnapAction, in visibleFrame: CGRect) -> CGRect? {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2

        switch action {
        case .leftHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .rightHalf:
            return CGRect(x: visibleFrame.minX + halfWidth, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .topHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY + halfHeight, width: visibleFrame.width, height: halfHeight)
        case .topLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: visibleFrame.minX + halfWidth, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY + halfHeight, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: visibleFrame.minX + halfWidth, y: visibleFrame.minY + halfHeight, width: halfWidth, height: halfHeight)
        case .maximize:
            return visibleFrame
        default:
            return nil
        }
    }

    private static func thirdFrame(for action: WindowSnapAction, in visibleFrame: CGRect) -> CGRect? {
        let thirdWidth = visibleFrame.width / 3

        switch action {
        case .leftThird:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: thirdWidth, height: visibleFrame.height)
        case .leftTwoThirds:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: thirdWidth * 2, height: visibleFrame.height)
        case .centerThird:
            return CGRect(x: visibleFrame.minX + thirdWidth, y: visibleFrame.minY, width: thirdWidth, height: visibleFrame.height)
        case .rightTwoThirds:
            return CGRect(x: visibleFrame.minX + thirdWidth, y: visibleFrame.minY, width: thirdWidth * 2, height: visibleFrame.height)
        case .rightThird:
            return CGRect(x: visibleFrame.maxX - thirdWidth, y: visibleFrame.minY, width: thirdWidth, height: visibleFrame.height)
        default:
            return nil
        }
    }

    /// Centers a window without resizing it, shrinking only when it cannot fit.
    static func centeredFrame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Where the minimize hint points during a titlebar swipe.
    static func minimizePreviewFrame(in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - 80,
            y: visibleFrame.maxY - 56,
            width: 160,
            height: 36
        )
    }

    /// Titlebar height assumed when a window exposes no traffic lights — hidden buttons, borderless
    /// windows, full screen.
    static let fallbackTitlebarHeight: CGFloat = 44

    private static let minimumTitlebarHeight: CGFloat = 24
    private static let maximumTitlebarHeight: CGFloat = 80

    /// Height of a window's titlebar, measured from where the system put its traffic lights.
    ///
    /// No constant can work here. Measured against real apps the titlebar is 32pt (cmux), 34pt
    /// (VS Code), 46pt (ChatGPT) and 52pt (Fork): 44pt reaches into the content of the first two
    /// and stops short of the toolbar in the last. The traffic lights sit in the titlebar and carry
    /// coordinates on native and Electron windows alike, so their inset is the only per-app
    /// measurement available from outside the process.
    static func titlebarHeight(windowFrame: CGRect, trafficLights: CGRect?) -> CGFloat {
        guard let trafficLights, !trafficLights.isEmpty else { return fallbackTitlebarHeight }

        let inset = trafficLights.minY - windowFrame.minY
        guard inset >= 0, inset <= maximumTitlebarHeight else { return fallbackTitlebarHeight }

        let height = trafficLights.maxY + inset - windowFrame.minY
        return min(max(height, minimumTitlebarHeight), maximumTitlebarHeight)
    }

    /// Whether a point falls inside the window's titlebar band, in Accessibility space.
    static func isInTitlebar(_ point: CGPoint, windowFrame: CGRect, trafficLights: CGRect?) -> Bool {
        guard point.x >= windowFrame.minX, point.x <= windowFrame.maxX, point.y >= windowFrame.minY else {
            return false
        }
        return point.y <= windowFrame.minY + titlebarHeight(windowFrame: windowFrame, trafficLights: trafficLights)
    }

    /// Mirrors a rect about `referenceMaxY`. Its own inverse, so the same function converts
    /// Accessibility → Cocoa and Cocoa → Accessibility.
    ///
    /// `referenceMaxY` has to be the **primary** display's `frame.maxY` — the display sitting at the
    /// Cocoa origin, the one holding the menu bar — because Accessibility `y = 0` is that display's
    /// top edge. Passing the highest `maxY` across all displays shifts every frame by the height of
    /// whatever sits above the primary one.
    static func flip(_ rect: CGRect, aboutMaxY referenceMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: referenceMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Re-places a window on another display, keeping its relative position and size so a half-tile
    /// on one screen stays a half-tile on the next, and clamps it fully inside the target's visible
    /// area instead of cropping it when the displays differ in aspect ratio.
    static func transferredFrame(_ frame: CGRect, from sourceVisible: CGRect, to targetVisible: CGRect) -> CGRect {
        guard sourceVisible.width > 0, sourceVisible.height > 0,
              targetVisible.width > 0, targetVisible.height > 0 else {
            return targetVisible
        }

        let width = min(frame.width / sourceVisible.width * targetVisible.width, targetVisible.width)
        let height = min(frame.height / sourceVisible.height * targetVisible.height, targetVisible.height)
        let relativeX = (frame.minX - sourceVisible.minX) / sourceVisible.width
        let relativeY = (frame.minY - sourceVisible.minY) / sourceVisible.height
        let proposedX = targetVisible.minX + relativeX * targetVisible.width
        let proposedY = targetVisible.minY + relativeY * targetVisible.height

        return CGRect(
            x: min(max(proposedX, targetVisible.minX), targetVisible.maxX - width),
            y: min(max(proposedY, targetVisible.minY), targetVisible.maxY - height),
            width: width,
            height: height
        )
    }

    static func framesApproximatelyEqual(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat = placementTolerance
    ) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}
