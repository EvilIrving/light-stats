//
//  SnapIslandViewModel.swift
//  Light Stats
//

import Foundation
import Observation

/// View-facing state for the layout island.
///
/// Split from the controller so the SwiftUI tree has one small observable object and the controller
/// keeps the window, the animation driver, and the drop bookkeeping. `@Observable` (rather than
/// `ObservableObject`) matches the rest of the newer view models in the project.
@Observable
final class SnapIslandViewModel {

    /// Layouts the user pinned, in order.
    var layouts: [SnapLayout] = []
    /// Which layout's segments are shown in the expanded state.
    var activeLayoutID: String?
    /// Segment currently under the pointer, so it can be highlighted before the drop.
    var hoveredSegmentID: String?
    /// Chip currently under the pointer.
    var hoveredLayoutID: String?
    /// Drives the panel's corner radii and its shadow, so both grow with the expansion.
    var openProgress: Double = 0
    /// Whether the full panel with the segment grid is showing. Distinct from `openProgress`:
    /// a collapsed strip can be tall enough to have room for the grid, and drawing it there would
    /// put drop targets on screen that the controller never hit-tests.
    var isExpanded: Bool = false
    /// The size the view lays its tiles out for — the destination of the current transition, not the
    /// panel's animating frame. Drawing against the animating frame would move every tile under the
    /// pointer while the panel grows, and the drop would land somewhere the user did not aim.
    var contentSize: CGSize = .zero
    var screenSize: CGSize = SnapLayoutProjection.referenceSize
    var collapsedSize = CGSize(width: 184, height: 32)

    var activeLayout: SnapLayout? {
        layouts.first { $0.id == activeLayoutID } ?? layouts.first
    }

    func reset() {
        hoveredSegmentID = nil
        hoveredLayoutID = nil
    }
}
