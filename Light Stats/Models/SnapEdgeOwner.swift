//
//  SnapEdgeOwner.swift
//  Light Stats
//

import Foundation

/// Which implementation owns the drag-to-edge gesture.
///
/// macOS ships the same gesture (macOS 15+: drag a window to a screen edge or the menu bar to tile
/// it), and two implementations of one gesture cannot both be live: both act on the same mouse-up,
/// and which one the user ends up seeing depends on which finished last. Exactly one of them has to
/// own it, so the choice is a single value rather than two independent switches.
///
/// Deliberately not a `Bool`: "Light Stats' zones off" is not a state the gesture can be in on its
/// own — it is a handover, and the system's copy takes over in the same move.
enum SnapEdgeOwner: String, Codable, Sendable, CaseIterable {
    /// Light Stats places the window: thirds, quarters, custom layouts, the island.
    case lightStats
    /// macOS tiles it. Halves and quarters only, no gaps, no layouts, no island.
    case system
}
