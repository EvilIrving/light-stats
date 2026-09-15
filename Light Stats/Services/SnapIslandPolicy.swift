//
//  SnapIslandPolicy.swift
//  Light Stats
//

import CoreGraphics

/// Geometry and hit-testing for the top-edge layout island. Pure, so the whole feel of the island
/// can be described by tests instead of by launching it.
nonisolated enum SnapIslandPolicy {

    /// The island hangs from the display's top edge and grows downward, so its `minY` is always the
    /// screen's `minY` — that is what makes it look like it grows out of the edge rather than
    /// scaling up in mid-air.
    static func frame(
        for state: SnapIslandState,
        in screen: CGRect,
        configuration: SnapIslandConfiguration
    ) -> CGRect {
        let width = state == .collapsed ? min(configuration.width(for: screen), 184) : configuration.width(for: screen)
        let height = state == .collapsed
            ? configuration.collapsedHeight(for: screen)
            : min(max(configuration.expandedHeight, configuration.collapsedHeight(for: screen)), max(screen.height, 0))
        return CGRect(
            x: screen.midX - width / 2,
            y: screen.minY,
            width: width,
            height: height
        )
    }

    /// Whether the pointer has armed the island on the top boundary.
    ///
    /// Mirrors `SnapZonePolicy`'s centred band, but takes the tolerance here rather than the zone
    /// threshold: the pointer may sit a little above the boundary because the window cannot follow
    /// it there.
    static func isActivated(
        pointer: CGPoint,
        screen: SnapScreenGeometry,
        configuration: SnapIslandConfiguration,
        zoneConfiguration: SnapZoneConfiguration
    ) -> Bool {
        guard zoneConfiguration.topEdgeMode == .island else { return false }
        let boundary = screen.visibleFrame.minY
        guard pointer.y - boundary <= zoneConfiguration.edgeThreshold else { return false }
        guard pointer.y - boundary >= -configuration.activationTolerance else { return false }

        let bandWidth = screen.frame.width * min(max(zoneConfiguration.islandCenterWidthRatio, 0.1), 1)
        return abs(pointer.x - screen.frame.midX) <= bandWidth / 2
    }

    /// Whether the pointer is on a segment of the island's expanded panel.
    ///
    /// Segment rects are laid out inside the panel itself with the same grid geometry the final
    /// placement uses, so what the user aims at is what the window becomes.
    static func segment(
        at point: CGPoint,
        panel: CGRect,
        layout: SnapLayout,
        margins: SnapMargins
    ) -> SnapSegment? {
        let content = panel.insetBy(dx: SnapIslandMetrics.contentInset, dy: SnapIslandMetrics.contentInset)
        for segment in layout.segments {
            let rect = SnapGridGeometry.frame(for: segment.rect, in: content, margins: margins)
            if rect.contains(point) { return segment }
        }
        return nil
    }
}
