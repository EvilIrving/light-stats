//
//  SnapMotion.swift
//  Light Stats
//

import Foundation

/// The kind of transition an island or preview is performing.
///
/// This is split out of the animation parameters because the same two frames can mean different
/// things: `resize` moves and resizes in place, while `show` is a first appearance. Treating
/// `resize` as a fresh `show` is exactly what makes an island visibly blink when the screen or the
/// layout changes mid-interaction.
enum SnapMotion: String, Sendable, CaseIterable {
    /// First appearance from nothing.
    case show
    /// Growing from the collapsed strip into the full panel.
    case expand
    /// Falling back from the full panel to the collapsed strip.
    case collapse
    /// Leaving entirely.
    case hide
    /// Same state, different geometry — a screen change or a layout change.
    case resize

    /// Whether the motion starts from an invisible window. `show` fades in; the rest start visible.
    var startsHidden: Bool { self == .show }

    /// Whether the window keeps its alpha. Hiding fades out, everything else stays opaque.
    var changesAlpha: Bool {
        switch self {
        case .show, .hide: return true
        case .expand, .collapse, .resize: return false
        }
    }
}
