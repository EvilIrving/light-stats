//
//  SnapIslandConfiguration.swift
//  Light Stats
//

import CoreGraphics

/// Geometry and activation rules for the top-edge layout island.
///
/// Wins exposes four separate tunables (`topOverflowTolerance`, `horizontalTolerance`,
/// `collapsedPreviewTopRatio`, `centerActivationWidthRatio`). Three of them are folded into
/// sensible constants here — they describe the same feel and nobody has ever asked for a slider on
/// "how far past the top edge counts as the top edge" — while the two that change the product's
/// character (how tall the strip is, how wide the activation band is) stay configurable.
struct SnapIslandConfiguration: Codable, Hashable, Sendable {

    /// Height of the collapsed strip as a fraction of the screen's height.
    var collapsedHeightRatio: Double
    /// Height of the expanded panel in points.
    var expandedHeight: CGFloat
    /// The island never grows wider than this, however wide the display is.
    var maximumWidth: CGFloat
    /// How far the pointer may sit past the screen's top edge and still count as "at the top".
    var activationTolerance: CGFloat
    /// Fraction of the screen's width, centred, in which the top edge opens the island.
    var centerWidthRatio: Double

    static let `default` = SnapIslandConfiguration(
        collapsedHeightRatio: 0.075,
        expandedHeight: 156,
        maximumWidth: 560,
        activationTolerance: 24,
        centerWidthRatio: 0.5
    )

    /// Collapsed strip height on a given display, clamped so it stays reachable on very small and
    /// very large screens alike.
    func collapsedHeight(for screen: CGRect) -> CGFloat {
        min(max(screen.height * collapsedHeightRatio, 24), 32, max(screen.height, 0))
    }

    /// Centred width that both states share, so expanding only changes the height and the island
    /// appears to grow out of the top rather than rescale.
    func width(for screen: CGRect) -> CGFloat {
        max(min(max(screen.width - 24, 0), maximumWidth), 0)
    }
}
