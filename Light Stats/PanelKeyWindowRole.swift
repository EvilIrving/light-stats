//
//  PanelKeyWindowRole.swift
//  Light Stats
//
//  Which window held the keyboard when the panel closed.
//
//  Recorded as a semantic role instead of an AppKit class name: `AppKitWindow` and
//  `_NSAlertPanel` are neither stable across macOS releases nor readable by whoever
//  opens a support report — and they cannot say whether the window was ours.
//

import Foundation

enum PanelKeyWindowRole: String, Sendable {
    case none
    case panel
    case settings
    case about
    case alert
    case other

    /// One of our own windows has the keyboard, so the panel gave up focus for a reason
    /// we caused ourselves rather than losing it for no reason.
    var isOwnWindow: Bool {
        switch self {
        case .panel, .settings, .about, .alert: return true
        case .none, .other: return false
        }
    }

    static let aboutIdentifier = "LightStatsAbout"

    static func resolve(
        className: String?,
        identifier: String?,
        isModal: Bool,
        isOwnedPanel: Bool
    ) -> PanelKeyWindowRole {
        guard className != nil else { return .none }
        if isOwnedPanel { return .panel }
        if isModal { return .alert }
        if className?.contains("Alert") == true { return .alert }
        if identifier == aboutIdentifier { return .about }
        if identifier?.localizedCaseInsensitiveContains("settings") == true { return .settings }
        return .other
    }
}
