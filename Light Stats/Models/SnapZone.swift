//
//  SnapZone.swift
//  Light Stats
//

import Foundation

/// A screen edge or corner, independent of any action mapping.
///
/// The drag pipeline identifies *where* the pointer is; the mapping from zone to result is a
/// separate decision so the island can claim the top edge without the zone detector having to know
/// that the island exists.
enum SnapZone: String, Sendable, Hashable, CaseIterable {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case upperHalf
    case lowerHalf
    case leftThird
    case leftTwoThirds
    case centerThird
    case rightTwoThirds
    case rightThird
    case none

    /// The normalized tile this zone covers, in top-left-origin screen space.
    ///
    /// `.top` is the **full** area, not the top half: pushing a window against the top boundary
    /// has always meant "fill the screen", and the half-tile is a separate action the shortcuts
    /// and the island offer instead.
    var normalizedRect: SnapNormalizedRect? {
        switch self {
        case .left: return .leftHalf
        case .right: return .rightHalf
        case .top: return .full
        case .bottom: return .bottomHalf
        case .topLeft: return .topLeftQuarter
        case .topRight: return .topRightQuarter
        case .bottomLeft: return .bottomLeftQuarter
        case .bottomRight: return .bottomRightQuarter
        case .upperHalf: return .topHalf
        case .lowerHalf: return .bottomHalf
        case .leftThird: return SnapNormalizedRect(columns: 3, rows: 1, column: 0, row: 0)
        case .leftTwoThirds: return SnapNormalizedRect(columns: 3, rows: 1, column: 0, row: 0, columnSpan: 2)
        case .centerThird: return SnapNormalizedRect(columns: 3, rows: 1, column: 1, row: 0)
        case .rightTwoThirds: return SnapNormalizedRect(columns: 3, rows: 1, column: 1, row: 0, columnSpan: 2)
        case .rightThird: return SnapNormalizedRect(columns: 3, rows: 1, column: 2, row: 0)
        case .none: return nil
        }
    }

    /// Whether this zone is one of the four corners.
    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }
}
