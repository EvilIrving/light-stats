//
//  PermissionGuideFlight.swift
//  Light Stats
//

import CoreGraphics

/// The guide card's path from where the user clicked to the slot it docks into beside the System
/// Settings window: two rectangles, a duration, and the height of the arc between them.
///
/// A value, and only a value — the sampling that turns it into frames, and the dock geometry that
/// produces its destination, are `PermissionGuideGeometry` in Services. Nothing here draws or
/// measures; a model is a snapshot, not a curve.
///
/// **Coordinates are Cocoa screen points** (origin bottom-left, `y` up), matching every other
/// `CGRect` in the permission guide: the flight exists for exactly one consumer, `NSWindow.setFrame`.
/// The System Settings window arrives in Accessibility space and is flipped once, before it gets
/// here, by `ScreenGeometryProvider`.
nonisolated struct PermissionGuideFlight: Sendable, Equatable {

    /// 780 ms out, 600 ms back. The reverse is quicker because it is an undo, not an arrival.
    static let outwardDuration: TimeInterval = 0.78
    static let reverseDuration: TimeInterval = 0.60
    /// Under Reduce Motion. A shorter flight, not a jump: an instant one reads as a glitch.
    static let reducedDuration: TimeInterval = 0.20

    /// The look at both ends of the path.
    static let startCornerRadius: CGFloat = 12
    static let endCornerRadius: CGFloat = 24

    /// Lift above the higher of the two endpoints. A straight line between a button and a panel over
    /// the same window reads as a slide; the arc is what makes it read as a throw.
    static let apexHeight: CGFloat = 160

    var startFrame: CGRect
    var endFrame: CGRect
    var duration: TimeInterval
    var apexHeight: CGFloat

    init(
        startFrame: CGRect,
        endFrame: CGRect,
        duration: TimeInterval = PermissionGuideFlight.outwardDuration,
        apexHeight: CGFloat = PermissionGuideFlight.apexHeight
    ) {
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.duration = duration
        self.apexHeight = apexHeight
    }

    /// The same path run backwards, from wherever the card currently rests.
    func reversed(duration: TimeInterval = PermissionGuideFlight.reverseDuration) -> PermissionGuideFlight {
        PermissionGuideFlight(
            startFrame: endFrame,
            endFrame: startFrame,
            duration: duration,
            apexHeight: apexHeight
        )
    }
}
