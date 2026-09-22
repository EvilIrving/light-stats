//
//  AppSwitcherLayout.swift
//  Light Stats
//

import AppKit
import CoreGraphics

/// Sizing for the switcher panel.
///
/// Pure and separate from the view, because "how many cards fit and how big are they" is arithmetic
/// with real edge cases — three windows, thirty windows, a narrow display — and it is much cheaper
/// to test than to look at.
nonisolated enum AppSwitcherLayout {

    // MARK: Window preview box

    static let preferredCardWidth: CGFloat = 200
    static let minimumCardWidth: CGFloat = 120
    /// The preview box may grow to fill the panel the application row asked for, but it is a preview,
    /// not a gallery: past this a single window would be blown up into a picture. Measured against
    /// the system switcher, whose row does not grow the panel any taller than the icons need.
    static let maximumCardWidth: CGFloat = 240
    static let cardSpacing: CGFloat = 10
    static let panelPadding: CGFloat = 14
    /// Height of the title bar under each thumbnail.
    static let cardTitleHeight: CGFloat = 30
    static let appRowSpacing: CGFloat = 12
    /// The panel never touches the screen edge; the system keeps about this much on each side.
    static let screenMargin: CGFloat = 32
    /// The window cards themselves stop growing here, however wide the panel becomes.
    static let maximumPanelWidth: CGFloat = 1_100

    // MARK: Application row

    /// The application row's geometry, copied from the system switcher.
    ///
    /// The system's row is one row of icons that **shrinks as the count grows** so it always fits the
    /// screen — there is no scroll bar in it, and nothing to scroll. Measured on macOS 26: a 17-app
    /// row stands about 85pt tall, i.e. icons around 76–80pt with ~10pt between them. Past the point
    /// where the icons would go below `minimumIconSize` the row wraps into further rows, which is what
    /// the system does too rather than shrinking into illegibility.
    enum AppChip {
        /// Space between the icon and the edge of its selection plate.
        static let platePadding: CGFloat = 8
        static let spacing: CGFloat = 10
        static let minimumIconSize: CGFloat = 28
        static let maximumIconSize: CGFloat = 80

        static func cellSize(iconSize: CGFloat) -> CGFloat { iconSize + platePadding * 2 }
    }

    struct AppRow: Hashable {
        var iconSize: CGFloat
        var perRow: Int
        var rows: Int
        var height: CGFloat

        var isEmpty: Bool { rows == 0 }
    }

    /// Icon size for `count` applications inside `availableWidth`, and how many fit on a row.
    static func appRow(count: Int, availableWidth: CGFloat) -> AppRow {
        let count = max(count, 1)
        let spacing = AppChip.spacing
        let width = max(availableWidth, 1)
        let singleCell = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let singleIcon = singleCell - AppChip.platePadding * 2
        if singleIcon >= AppChip.minimumIconSize {
            let icon = min(singleIcon, AppChip.maximumIconSize)
            return AppRow(iconSize: icon, perRow: count, rows: 1, height: AppChip.cellSize(iconSize: icon))
        }

        // Even the smallest icons need more than one row. How many fit per row is decided by the
        // smallest cell, then the icons are re-sized to use that row exactly.
        let smallestCell = AppChip.cellSize(iconSize: AppChip.minimumIconSize)
        let perRow = max(Int((width + spacing) / (smallestCell + spacing)), 1)
        let rows = Int(ceil(Double(count) / Double(perRow)))
        let wrappedCell = (width - spacing * CGFloat(perRow - 1)) / CGFloat(perRow)
        let icon = min(max(wrappedCell - AppChip.platePadding * 2, AppChip.minimumIconSize), AppChip.maximumIconSize)
        let height = AppChip.cellSize(iconSize: icon) * CGFloat(rows) + spacing * CGFloat(rows - 1)
        return AppRow(iconSize: icon, perRow: perRow, rows: rows, height: height)
    }

    /// Width of the application row: full rows of `perRow` cells, the last row shorter.
    static func appRowWidth(count: Int, iconSize: CGFloat, perRow: Int) -> CGFloat {
        let columns = max(min(perRow, max(count, 1)), 1)
        return CGFloat(columns) * AppChip.cellSize(iconSize: iconSize) + AppChip.spacing * CGFloat(columns - 1)
    }

    struct Metrics: Hashable {
        var panelSize: CGSize
        var cardSize: CGSize
        /// How many windows are drawn; the rest are summarised as an overflow chip.
        var visibleWindowCount: Int
        var overflowCount: Int
        /// `nil` when the application row is not drawn at all.
        var appRow: AppRow?
    }

    /// - Parameters:
    ///   - windowCount: windows belonging to the application being shown.
    ///   - appCount: applications in the row above it.
    ///   - available: the space the panel may occupy — a display's visible frame, edge to edge. The
    ///     margins the panel keeps are this type's business, not the caller's.
    ///   - showsAppRow: whether the application row is drawn.
    static func metrics(
        windowCount: Int,
        appCount: Int,
        available: CGSize,
        showsAppRow: Bool
    ) -> Metrics {
        let count = max(windowCount, 1)
        let limit = max(available.width - screenMargin * 2, minimumCardWidth + panelPadding * 2)
        let contentLimit = limit - panelPadding * 2

        let appRow = showsAppRow ? appRow(count: appCount, availableWidth: contentLimit) : nil
        let rowWidth = appRow.map { appRowWidth(count: appCount, iconSize: $0.iconSize, perRow: $0.perRow) } ?? 0

        let gaps = cardSpacing * CGFloat(max(count - 1, 0))
        let idealCards = CGFloat(count) * preferredCardWidth + gaps
        let contentWidth = max(rowWidth, min(idealCards, maximumPanelWidth - panelPadding * 2))
        let panelWidth = min(contentWidth + panelPadding * 2, limit)
        let usableWidth = max(panelWidth - panelPadding * 2, minimumCardWidth)
        let cardWidth = min(max((usableWidth - gaps) / CGFloat(count), minimumCardWidth), maximumCardWidth)

        // With the minimum card width fixed, the number that actually fits is the number the strip
        // can hold; anything beyond that is summarised rather than shrunk into illegibility.
        let perCard = cardWidth + cardSpacing
        let fits = max(Int((usableWidth + cardSpacing) / perCard), 1)
        let visible = min(count, fits)
        let overflow = count - visible

        let cardHeight = cardWidth * 0.62 + cardTitleHeight
        let height = panelPadding * 2
            + cardHeight
            + (appRow.map { $0.height + appRowSpacing } ?? 0)

        return Metrics(
            panelSize: CGSize(width: panelWidth, height: height),
            cardSize: CGSize(width: cardWidth, height: cardHeight),
            visibleWindowCount: visible,
            overflowCount: overflow,
            appRow: appRow
        )
    }

    /// Width the content is centred in: the panel minus its padding.
    static func contentWidth(for metrics: Metrics) -> CGFloat {
        max(metrics.panelSize.width - panelPadding * 2, 1)
    }

    /// Where the switcher panel sits: centred horizontally, a little above the middle of the screen
    /// so it never lands under the pointer or the Dock.
    static func panelFrame(size: CGSize, available: CGRect) -> CGRect {
        let x = available.midX - size.width / 2
        let centred = available.minY + (available.height - size.height) / 2
        // A third of the way up reads better than dead centre and keeps clear of the Dock.
        let y = centred + available.height * 0.08
        return CGRect(
            x: min(max(x, available.minX), max(available.maxX - size.width, available.minX)),
            y: min(max(y, available.minY), max(available.maxY - size.height, available.minY)),
            width: size.width,
            height: size.height
        )
    }
}

/// Sizing for the Dock hover preview.
nonisolated enum DockPreviewLayout {

    static let preferredCardWidth: CGFloat = 190
    static let minimumCardWidth: CGFloat = 108
    static let cardSpacing: CGFloat = 10
    static let panelPadding: CGFloat = 12
    static let headerHeight: CGFloat = 30
    static let cardTitleHeight: CGFloat = 30
    static let maximumPanelWidth: CGFloat = 900

    struct Metrics: Hashable {
        var panelSize: CGSize
        var cardSize: CGSize
        var visibleWindowCount: Int
        var overflowCount: Int
    }

    static func metrics(windowCount: Int, available: CGSize) -> Metrics {
        let count = max(windowCount, 1)
        let usableWidth = max(min(available.width, maximumPanelWidth) - panelPadding * 2, minimumCardWidth)
        let gaps = cardSpacing * CGFloat(max(count - 1, 0))
        let idealWidth = (usableWidth - gaps) / CGFloat(count)
        let cardWidth = min(max(idealWidth, minimumCardWidth), preferredCardWidth)
        let perCard = cardWidth + cardSpacing
        let fits = max(Int((usableWidth + cardSpacing) / perCard), 1)
        let visible = min(count, fits)

        let cardHeight = cardWidth * 0.62 + cardTitleHeight
        let contentWidth = CGFloat(visible) * cardWidth + cardSpacing * CGFloat(max(visible - 1, 0))
        let height = panelPadding * 2 + headerHeight + cardHeight

        return Metrics(
            panelSize: CGSize(width: contentWidth + panelPadding * 2, height: height),
            cardSize: CGSize(width: cardWidth, height: cardHeight),
            visibleWindowCount: visible,
            overflowCount: count - visible
        )
    }
}
