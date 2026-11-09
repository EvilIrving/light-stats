//
//  PermissionGuideCardState.swift
//  Light Stats
//

import CoreGraphics
import Foundation
import Observation

/// Everything the guide card draws, mutable from the animation that carries it.
///
/// One observable box rather than six bindings: the window drives the corner radius, the shadow, and
/// the settled phase from three different call sites. It is view state, not a service facade — there
/// is nothing behind it but a flight being sampled — but it is observable snapshot state, which is
/// the ViewModels layer's shape and where `@Observable` belongs.
@MainActor
@Observable
final class PermissionGuideCardState {

    /// What the card is asking for right now.
    ///
    /// `relaunchRequired` is not a success message and not a failure: Screen Recording's preflight is
    /// cached for the life of the process, so a real grant cannot be read back, and the only honest
    /// thing the card can say is "if you allowed it, restart".
    enum Phase: Sendable, Equatable {
        case guiding
        case relaunchRequired
    }

    var phase: Phase = .guiding
    var pane: PermissionPane
    /// Which side of the Settings window the card rests on, which is also which way the arrow points.
    var side: PermissionGuideDockSide
    var appName: String
    /// `nil` when the bundle cannot be dragged (translocated, or not an `.app`).
    var dropBundleURL: URL?
    var cornerRadius: CGFloat = PermissionGuideFlight.startCornerRadius
    var shadowOpacity: Double = 0
    var onBack: @MainActor () -> Void = {}
    var onRelaunch: @MainActor () -> Void = {}

    init(pane: PermissionPane, side: PermissionGuideDockSide, appName: String, dropBundleURL: URL?) {
        self.pane = pane
        self.side = side
        self.appName = appName
        self.dropBundleURL = dropBundleURL
    }
}
