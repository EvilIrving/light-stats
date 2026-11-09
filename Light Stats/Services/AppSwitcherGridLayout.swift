//
//  AppSwitcherGridLayout.swift
//  Light Stats
//

import CoreGraphics

/// Sizing for the grid mode: one tile per window, as many columns as the screen takes before the
/// tiles have to shrink, and never larger than the screen allows.
///
/// The two-level mode answers "how many cards fit in a row"; this answers "how many rows fit", and
/// normally that is the whole difference between the modes — no overflow chip, nothing to scroll.
///
/// It stops being true at a window count no layout can fold: the tile has a readable minimum width
/// and the card has a fixed aspect, so past a certain count the rows simply do not fit any display.
/// The panel is then capped at `maximumScreenFraction` of the screen and the view scrolls inside it
/// (`Metrics.isScrollable`), which is the one thing this mode may never do instead: grow taller
/// than the screen, taking the selected tile with it off the visible area.
nonisolated enum AppSwitcherGridLayout {

    static let spacing: CGFloat = AppSwitcherLayout.cardSpacing
    static let padding: CGFloat = AppSwitcherLayout.panelPadding
    static let maximumColumns = 6
    static let preferredTileWidth: CGFloat = 208
    /// Below this the title line and the picture stop being readable, so the panel grows columns
    /// instead of shrinking further.
    static let minimumTileWidth: CGFloat = 128
    private static let tileAspect: CGFloat = 0.62
    private static let maximumScreenFraction: CGFloat = 0.9

    struct Metrics: Hashable {
        var columns: Int
        var tileSize: CGSize
        var panelSize: CGSize
        /// The grid's own height before the panel caps it. Larger than `panelSize` means the rows do
        /// not fit the screen and the view has to scroll.
        var contentHeight: CGFloat

        var contentWidth: CGFloat {
            max(panelSize.width - AppSwitcherGridLayout.padding * 2, 1)
        }

        /// Whether the grid is taller than the panel it is drawn in — the only case that scrolls.
        var isScrollable: Bool { contentHeight > panelSize.height + 0.5 }
    }

    static func metrics(windowCount: Int, available: CGSize) -> Metrics {
        let count = max(windowCount, 1)
        let maxWidth = max(available.width * maximumScreenFraction, 1)
        let maxHeight = max(available.height * maximumScreenFraction, 1)
        let columnsByWidth = max(
            Int((maxWidth - padding * 2 + spacing) / (minimumTileWidth + spacing)),
            1
        )
        let columnLimit = min(count, min(maximumColumns, columnsByWidth))

        var columns = min(count, 4)
        while columns < columnLimit, panelHeight(count: count, columns: columns, tileHeight: preferredTileHeight) > maxHeight {
            columns += 1
        }

        let rows = rows(count: count, columns: columns)
        let heightBudget = (maxHeight - padding * 2 - CGFloat(rows - 1) * spacing) / CGFloat(rows)
        let titleHeight = AppSwitcherLayout.cardTitleHeight
        let minimumHeight = minimumTileWidth * tileAspect + titleHeight
        let heightLimit = max(minimumHeight, min(preferredTileHeight, heightBudget))

        let widthBudget = (maxWidth - padding * 2 - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let widthFromHeight = (heightLimit - titleHeight) / tileAspect
        let tileWidth = max(min(preferredTileWidth, widthFromHeight, widthBudget), 0)
        // The card draws its picture at this aspect above a fixed title line, so the height follows
        // the width that was actually available. Taking the height budget alone would leave a narrow
        // display with tiles taller than their own aspect — the same card, a different shape.
        let tileHeight = tileWidth * tileAspect + titleHeight

        // The tile has a floor — a readable width — and the card has a fixed aspect, so the grid's
        // height follows from the width and can outgrow any display. The panel is capped and the
        // view scrolls; the alternative is a panel taller than the screen, whose selected tile is
        // not where the user is looking.
        let contentHeight = panelHeight(count: count, columns: columns, tileHeight: tileHeight)
        let contentWidth = CGFloat(columns) * tileWidth + CGFloat(columns - 1) * spacing + padding * 2

        return Metrics(
            columns: columns,
            tileSize: CGSize(width: tileWidth, height: tileHeight),
            panelSize: CGSize(width: min(contentWidth, maxWidth), height: min(contentHeight, maxHeight)),
            contentHeight: contentHeight
        )
    }

    private static var preferredTileHeight: CGFloat {
        preferredTileWidth * tileAspect + AppSwitcherLayout.cardTitleHeight
    }

    private static func rows(count: Int, columns: Int) -> Int {
        Int((Double(count) / Double(columns)).rounded(.up))
    }

    private static func panelHeight(count: Int, columns: Int, tileHeight: CGFloat) -> CGFloat {
        let rows = rows(count: count, columns: columns)
        return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * spacing + padding * 2
    }
}
