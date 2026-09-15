//
//  SnapZoneConfiguration.swift
//  Light Stats
//

import CoreGraphics

/// What the pointer can trigger while a window is being dragged.
struct SnapZoneConfiguration: Codable, Hashable, Sendable {

    /// Drag a window to a screen edge to tile it there.
    var edgesEnabled: Bool
    /// The screen corners tile into a quarter instead of a half.
    var cornersEnabled: Bool
    /// What the top edge does: island, plain maximize, or nothing.
    var topEdgeMode: SnapTopEdgeMode
    /// How close the pointer has to get to an edge, in points.
    var edgeThreshold: CGFloat
    /// Fraction of the screen's width, measured from each side, that forms a corner zone.
    var cornerWidthRatio: Double
    /// Fraction of the screen's width, centred, in which the top edge opens the island.
    var islandCenterWidthRatio: Double
    /// How far past a screen boundary the pointer may be and still count. The pointer is allowed
    /// into the menu bar and over the Dock, so a drag can overshoot the edge by a little.
    var offscreenTolerance: CGFloat

    static let `default` = SnapZoneConfiguration(
        edgesEnabled: true,
        cornersEnabled: true,
        topEdgeMode: .island,
        edgeThreshold: 24,
        cornerWidthRatio: 0.18,
        islandCenterWidthRatio: 0.5,
        offscreenTolerance: 48
    )

    /// No drag detection at all, used when the whole drag pipeline is off.
    static let disabled = SnapZoneConfiguration(
        edgesEnabled: false,
        cornersEnabled: false,
        topEdgeMode: .disabled,
        edgeThreshold: 0,
        cornerWidthRatio: 0,
        islandCenterWidthRatio: 0,
        offscreenTolerance: 0
    )

    var isActive: Bool {
        edgesEnabled || cornersEnabled || topEdgeMode != .disabled
    }
}

/// What the top edge of a screen does during a drag.
enum SnapTopEdgeMode: String, Codable, Sendable, CaseIterable {
    /// Open the layout island when the pointer crosses the top edge near the screen's centre.
    case island
    /// Tile the window to the full visible area, no island.
    case maximize
    /// Ignore the top edge entirely.
    case disabled
}
