//
//  SnapIslandLayout.swift
//  Light Stats
//

import CoreGraphics

/// Every layout is directly droppable. The rendered tiles and release hit tests use these exact rectangles.
nonisolated enum SnapIslandLayout {
    struct Tile {
        var layoutID: String
        var segment: SnapSegment
        var frame: CGRect
        var id: String { "\(layoutID)/\(segment.id)" }
    }

    static func columnCount(layoutCount: Int, width: CGFloat) -> Int {
        min(max(Int(max(width, 0) / 104), 1), max(layoutCount, 1))
    }

    static func preferredHeight(layoutCount: Int, width: CGFloat, sourceSize: CGSize) -> CGFloat {
        let contentWidth = max(width - 2 * SnapIslandMetrics.contentInset, 0)
        let columns = columnCount(layoutCount: layoutCount, width: contentWidth)
        let rows = max((layoutCount + columns - 1) / columns, 1)
        let tileWidth = max((contentWidth - CGFloat(columns - 1) * SnapIslandMetrics.chipSpacing) / CGFloat(columns), 0)
        let ratio = sourceSize.width > 0 ? sourceSize.height / sourceSize.width : 0.625
        return CGFloat(rows) * min(max(tileWidth * ratio, 64), 120)
            + CGFloat(rows - 1) * SnapIslandMetrics.chipSpacing + 2 * SnapIslandMetrics.contentInset
    }

    static func layoutFrames(layouts: [SnapLayout], panel: CGRect) -> [(id: String, frame: CGRect)] {
        guard !layouts.isEmpty else { return [] }
        let content = panel.insetBy(dx: SnapIslandMetrics.contentInset, dy: SnapIslandMetrics.contentInset)
        guard content.width > 0, content.height > 0 else { return [] }
        let columns = columnCount(layoutCount: layouts.count, width: content.width)
        let rows = (layouts.count + columns - 1) / columns
        let gap = SnapIslandMetrics.chipSpacing
        let width = max((content.width - CGFloat(columns - 1) * gap) / CGFloat(columns), 0)
        let height = max((content.height - CGFloat(rows - 1) * gap) / CGFloat(rows), 0)
        return layouts.enumerated().map { index, layout in
            (layout.id, CGRect(x: content.minX + CGFloat(index % columns) * (width + gap),
                              y: content.minY + CGFloat(index / columns) * (height + gap), width: width, height: height))
        }
    }

    static func tiles(
        layouts: [SnapLayout], panel: CGRect, margins: SnapMargins,
        sourceSize: CGSize = SnapLayoutProjection.referenceSize
    ) -> [Tile] {
        layoutFrames(layouts: layouts, panel: panel).flatMap { entry -> [Tile] in
            guard let layout = layouts.first(where: { $0.id == entry.id }) else { return [] }
            return layout.segments.map { segment in
                Tile(layoutID: layout.id, segment: segment, frame: SnapLayoutProjection.frame(
                    for: segment.rect, in: entry.frame, margins: margins, sourceSize: sourceSize
                ))
            }
        }
    }

    static func hit(
        at point: CGPoint, layouts: [SnapLayout], panel: CGRect, margins: SnapMargins,
        sourceSize: CGSize = SnapLayoutProjection.referenceSize
    ) -> Tile? {
        tiles(layouts: layouts, panel: panel, margins: margins, sourceSize: sourceSize).first { $0.frame.contains(point) }
    }
}
