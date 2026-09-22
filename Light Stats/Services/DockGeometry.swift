//
//  DockOrientation.swift
//  Light Stats
//

import CoreGraphics

/// Which edge the Dock is docked to.
///
/// Read from `com.apple.dock`'s `orientation` key rather than inferred from the visible-frame gap:
/// an auto-hidden Dock reserves no space at all, so the gap would be zero and the inference would
/// have nothing to work with.
enum DockOrientation: String, Sendable, CaseIterable {
    case bottom
    case left
    case right
    /// The Dock cannot actually be moved to the top, but the preference can hold the value and
    /// silently ignoring it would put the preview in the wrong place for those users.
    case top

    var isHorizontal: Bool { self == .bottom || self == .top }

    /// The edge the preview panel must stay clear of.
    var reservedEdge: Edge {
        switch self {
        case .bottom: return .bottom
        case .left: return .left
        case .right: return .right
        case .top: return .top
        }
    }

    enum Edge: String, Sendable, CaseIterable {
        case top, bottom, left, right
    }
}

/// Geometry for the Dock band and the hover preview panel that sits next to it.
///
/// Pure, so the placement — above a bottom Dock, beside a side Dock, clamped so a preview near the
/// screen corner does not run off the edge — is covered by tests rather than by moving a mouse to
/// every corner of the screen.
nonisolated enum DockGeometry {

    /// Distance between the Dock and the preview panel.
    static let panelGap: CGFloat = 10

    /// The region the Dock occupies on this display, in Cocoa coordinates.
    ///
    /// Normally the difference between the display frame and its visible frame — that is exactly
    /// menu bar plus Dock. An auto-hidden Dock reserves nothing, so `fallbackDockFrame` supplies the
    /// real rectangle that Accessibility reports while the Dock is revealed.
    static func band(
        screen: CGRect,
        visibleFrame: CGRect,
        orientation: DockOrientation,
        fallbackDockFrame: CGRect?
    ) -> CGRect {
        let thickness: CGFloat
        switch orientation {
        case .bottom: thickness = max(visibleFrame.minY - screen.minY, 0)
        case .top: thickness = max(screen.maxY - visibleFrame.maxY, 0)
        case .left: thickness = max(visibleFrame.minX - screen.minX, 0)
        case .right: thickness = max(screen.maxX - visibleFrame.maxX, 0)
        }

        // A plausible Dock is at least a few points thick. Below that the reserved space is the menu
        // bar (top) or genuinely nothing (auto-hide), and the reported frame is the better answer.
        let minimumBand: CGFloat = 8
        if thickness >= minimumBand, orientation != .top {
            switch orientation {
            case .bottom:
                return CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: thickness)
            case .left:
                return CGRect(x: screen.minX, y: screen.minY, width: thickness, height: screen.height)
            case .right:
                return CGRect(x: screen.maxX - thickness, y: screen.minY, width: thickness, height: screen.height)
            case .top:
                break
            }
        }
        return fallbackDockFrame ?? .zero
    }

    /// Where the preview panel goes, anchored to the hovered Dock item.
    ///
    /// - Parameters:
    ///   - anchor: the Dock item's rect, Cocoa. `nil` centres the panel on its edge instead.
    ///   - band: the Dock's own region, from `band(screen:visibleFrame:orientation:fallbackDockFrame:)`.
    ///   - available: the area the panel must stay inside — the display's visible frame.
    static func previewFrame(
        anchoredTo anchor: CGRect?,
        band: CGRect,
        panelSize: CGSize,
        available: CGRect,
        orientation: DockOrientation
    ) -> CGRect {
        var origin: CGPoint

        switch orientation {
        case .bottom:
            let x = anchor?.midX ?? available.midX
            origin = CGPoint(x: x - panelSize.width / 2, y: band.maxY + panelGap)
        case .top:
            let x = anchor?.midX ?? available.midX
            origin = CGPoint(x: x - panelSize.width / 2, y: band.minY - panelGap - panelSize.height)
        case .left:
            let y = anchor?.midY ?? available.midY
            origin = CGPoint(x: band.maxX + panelGap, y: y - panelSize.height / 2)
        case .right:
            let y = anchor?.midY ?? available.midY
            origin = CGPoint(x: band.minX - panelGap - panelSize.width, y: y - panelSize.height / 2)
        }

        return clamp(
            CGRect(origin: origin, size: panelSize),
            inside: available,
            orientation: orientation
        )
    }

    /// The rectangle the panel grows out of when it first appears.
    ///
    /// The final frame scaled about the Dock icon it is anchored to, so the preview reads as coming
    /// out of the icon instead of fading in over it. Above a bottom Dock that means it expands
    /// upward from the icon's centre; the anchor point itself does not move.
    static func appearanceStartFrame(final: CGRect, anchor: CGRect, scale: CGFloat = 0.94) -> CGRect {
        guard final.width > 0, final.height > 0, anchor.width > 0, anchor.height > 0 else { return final }
        let centre = CGPoint(x: anchor.midX, y: anchor.midY)
        return CGRect(
            x: centre.x - (centre.x - final.minX) * scale,
            y: centre.y - (centre.y - final.minY) * scale,
            width: final.width * scale,
            height: final.height * scale
        )
    }

    /// Keeps the panel fully inside the visible area.
    ///
    /// Sliding along the Dock's own axis clips to the edge instead of overflowing, and — because
    /// there is nowhere to move to — the perpendicular axis is clamped to the edge nearest the Dock
    /// so a side Dock's panel never ends up on the wrong side of the screen.
    static func clamp(_ frame: CGRect, inside available: CGRect, orientation: DockOrientation) -> CGRect {
        guard available.width > 0, available.height > 0 else { return frame }
        var result = frame

        if orientation.isHorizontal {
            result.origin.x = min(max(result.minX, available.minX), max(available.maxX - result.width, available.minX))
        } else {
            result.origin.y = min(max(result.minY, available.minY), max(available.maxY - result.height, available.minY))
        }

        // If the panel is taller or wider than the available area there is nothing to clamp to; keep
        // the origin at the near edge rather than producing a negative one.
        result.origin.x = max(result.minX, available.minX)
        result.origin.y = max(result.minY, available.minY)
        return result
    }

    /// Whether a point is close enough to the Dock band to count as hovering it.
    ///
    /// The slack is what makes the gesture forgiving: nobody keeps the pointer exactly inside the
    /// Dock's rectangle while moving between two icons.
    static func isWithinDock(_ point: CGPoint, band: CGRect, slack: CGFloat) -> Bool {
        guard !band.isEmpty else { return false }
        return band.insetBy(dx: -slack, dy: -slack).contains(point)
    }
}
