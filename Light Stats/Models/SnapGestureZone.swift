//
//  SnapGestureZone.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import Foundation

/// Where a swipe has to start for the snap engine to accept it.
///
/// The two zones exist because a window's titlebar cannot be trusted from outside the process:
/// Electron apps draw their own, AppKit windows never expose one through Accessibility, and the
/// measured height differs per app. `pointer` is the escape hatch for exactly those windows.
enum SnapGestureZone: Sendable {
    /// The window's own titlebar band, and not on any of its controls.
    case titlebar
    /// Anywhere over the window, ignoring titlebar geometry and controls.
    case pointer

    /// Stable identifier used in diagnostics and rejection reasons.
    var diagnosticName: String {
        switch self {
        case .titlebar: return "titlebar"
        case .pointer: return "pointer"
        }
    }
}
