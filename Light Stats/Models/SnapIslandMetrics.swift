//
//  SnapIslandMetrics.swift
//  Light Stats
//

import CoreGraphics

/// The island's own chrome constants.
///
/// Kept apart from the placement geometry so a visual tweak can never move a window: nothing here
/// is ever handed to the placement engine, it only shapes the panel the user aims at.
enum SnapIslandMetrics {

    /// Padding between the panel edge and the tile grid.
    static let contentInset: CGFloat = 12
    /// Radius of the panel's lower corners. The top corners stay square so the panel reads as
    /// attached to the screen edge rather than floating below it.
    static let bottomCornerRadius: CGFloat = 14
    /// Height of the tile row inside the collapsed strip.
    static let collapsedTileHeight: CGFloat = 30
    /// Gutter between the layout chips, and between the chip row and the segment grid.
    static let chipSpacing: CGFloat = 8
    /// Corner radius of the small tiles drawn inside a chip.
    static let chipTileRadius: CGFloat = 2

    /// Tile colour presets, matching Wins' `floatingColor`.
    enum Palette: String, Codable, Sendable, CaseIterable {
        case neutral
        case accent
        case vivid
    }
}
