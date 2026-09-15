//
//  AppSwitcherLayout.swift
//  Light Stats
//

import CoreGraphics

/// Sizing for the switcher panel.
///
/// Pure and separate from the view, because "how many cards fit and how big are they" is arithmetic
/// with real edge cases — three windows, thirty windows, a narrow display — and it is much cheaper
/// to test than to look at.
nonisolated enum AppSwitcherLayout {

    static let preferredCardWidth: CGFloat = 224
    static let minimumCardWidth: CGFloat = 116
    static let cardSpacing: CGFloat = 10
    static let panelPadding: CGFloat = 14
    /// Height of the title bar under each thumbnail.
    static let cardTitleHeight: CGFloat = 34
    /// Height of the row of application chips above the window strip.
    static let appRowHeight: CGFloat = 46
    static let appRowSpacing: CGFloat = 10
    /// Below this the thumbnails stop being informative and the panel should not grow any further.
    static let maximumPanelWidth: CGFloat = 1_100

    struct Metrics: Hashable {
        var panelSize: CGSize
        var cardSize: CGSize
        /// How many windows are drawn; the rest are summarised as an overflow chip.
        var visibleWindowCount: Int
        var overflowCount: Int
    }

    /// - Parameters:
    ///   - windowCount: windows belonging to the application being shown.
    ///   - available: the space the panel may occupy (a display's visible frame, inset a little).
    ///   - showsAppRow: whether the application chips are drawn.
    static func metrics(windowCount: Int, available: CGSize, showsAppRow: Bool) -> Metrics {
        let count = max(windowCount, 1)
        let usableWidth = max(min(available.width, maximumPanelWidth) - panelPadding * 2, minimumCardWidth)
        let gaps = cardSpacing * CGFloat(max(count - 1, 0))
        let idealWidth = (usableWidth - gaps) / CGFloat(count)
        let cardWidth = min(max(idealWidth, minimumCardWidth), preferredCardWidth)

        // With the minimum card width fixed, the number that actually fits is the number the strip
        // can hold; anything beyond that is summarised rather than shrunk into illegibility.
        let perCard = cardWidth + cardSpacing
        let fits = max(Int((usableWidth + cardSpacing) / perCard), 1)
        let visible = min(count, fits)
        let overflow = count - visible

        let cardHeight = cardWidth * 0.62 + cardTitleHeight
        let contentWidth = CGFloat(visible) * cardWidth + cardSpacing * CGFloat(max(visible - 1, 0))
        let height = panelPadding * 2
            + cardHeight
            + (showsAppRow ? appRowHeight + appRowSpacing : 0)

        return Metrics(
            panelSize: CGSize(width: min(contentWidth + panelPadding * 2, available.width), height: height),
            cardSize: CGSize(width: cardWidth, height: cardHeight),
            visibleWindowCount: visible,
            overflowCount: overflow
        )
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
