//
//  ThemeDefinition.swift
//  Light Stats
//
//  Single composition table: AppTheme → UI + background + layout.
//  Four product presets are fixed here. Business views consume the resolved
//  parts and must not switch on `AppTheme` identity.
//

import Foundation

struct ThemeDefinition: Equatable {
    let ui: UITokens
    let background: BackgroundConfiguration
    let layout: ThemeLayout

    static func definition(for theme: AppTheme) -> ThemeDefinition {
        switch theme {
        case .glass: return .glass
        case .bento: return .bento
        case .film: return .film
        case .noir: return .noir
        }
    }

    /// Default — instrument chrome + system glass.
    static let glass = ThemeDefinition(
        ui: .glass,
        background: .glass,
        layout: .instrument
    )

    /// Bento — card grid + system glass.
    static let bento = ThemeDefinition(
        ui: .bento,
        background: .glass,
        layout: .bento
    )

    /// Sun Gold — film ink + warm mesh renderer.
    static let film = ThemeDefinition(
        ui: .film,
        background: .film,
        layout: .instrument
    )

    /// Ink Night — noir ink + cool mesh renderer.
    static let noir = ThemeDefinition(
        ui: .noir,
        background: .noir,
        layout: .instrument
    )
}
