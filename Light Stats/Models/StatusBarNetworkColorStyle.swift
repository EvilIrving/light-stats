//
//  StatusBarNetworkColorStyle.swift
//  Light Stats
//
//  Status-bar network tint vocabulary. `traffic` (blue up / green down) is kept
//  as the intended pair for the coloured draw path in `StatusBarView`, but that
//  path is product-gated off: coloured network forces the whole status item out
//  of menu-bar template tinting and reads noisy next to the other metrics.
//  Overview / panel network colouring is separate and stays as-is.
//

import Foundation

enum StatusBarNetworkColorStyle: String, CaseIterable, Identifiable, Sendable {
    /// Template-tinted with the rest of the status item.
    case system
    /// Blue upload / green download.
    case traffic

    var id: String { rawValue }
}
