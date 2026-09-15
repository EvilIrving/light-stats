//
//  SnapIslandState.swift
//  Light Stats
//

import Foundation

/// The island's resting states.
///
/// Only two, but the *transitions* between them are five (`SnapMotion`). Collapsing the two ideas
/// into one enum is what makes an island blink on a screen change: the code would treat "same
/// state, new geometry" as a fresh appearance instead of an in-place resize.
enum SnapIslandState: String, Sendable {
    /// The thin strip that appears as soon as a drag reaches the top.
    case collapsed
    /// The full panel with the layout tiles.
    case open

    /// The motion that gets from here to `next` without a visible appearance or disappearance.
    func motion(to next: SnapIslandState) -> SnapMotion {
        switch (self, next) {
        case (.collapsed, .open): return .expand
        case (.open, .collapsed): return .collapse
        case (.collapsed, .collapsed), (.open, .open): return .resize
        }
    }
}
