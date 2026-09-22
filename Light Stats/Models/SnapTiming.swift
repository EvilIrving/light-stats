//
//  SnapTiming.swift
//  Light Stats
//

import Foundation

/// How an island or preview transition is timed.
///
/// The spring case carries SwiftUI's vocabulary (`response`, `dampingFraction`) because that is the
/// feel this animation is matching and it is what a designer can reason about. It is sampled analytically
/// here rather than handed to an animation API, because the intermediate frames have to be readable
/// — the island changes its corner radii and shadow progress on the same timeline that moves it.
enum SnapTiming: Hashable, Sendable {

    /// A damped spring. `response` is the period of the undamped oscillation in seconds, and
    /// `dampingFraction` is 1 for no overshoot.
    case spring(response: Double, dampingFraction: Double)
    /// A named curve over a fixed duration.
    case curve(name: SnapCurve, duration: Double)

    static let islandExpand = SnapTiming.spring(response: 0.20, dampingFraction: 0.90)
    static let islandCollapse = SnapTiming.spring(response: 0.16, dampingFraction: 1)
    static let preview = SnapTiming.spring(response: 0.22, dampingFraction: 0.96)

    /// The shorter timeline used when the system asks for reduced motion.
    ///
    /// Reduce Motion is not "no animation" — it keeps a shorter one. Removing
    /// the transition entirely makes placement feel like a glitch rather than a deliberate act.
    static let reduced = SnapTiming.curve(name: .easeOut, duration: 0.08)
}

/// The curve names the animation sampler understands.
enum SnapCurve: String, Hashable, Sendable, CaseIterable {
    case linear
    case easeOut
    case easeInOut
}
