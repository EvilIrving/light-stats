//
//  ThemeDefinition.swift
//  Light Stats
//
//  Single composition table: AppTheme → UI + background + layout.
//  Product presets are fixed here. Business views consume the resolved
//  parts and must not switch on `AppTheme` identity.
//

import Foundation

struct ThemeDefinition: Equatable {
    let ui: UITokens
    let background: BackgroundSceneID
    let layout: ThemeLayout

    static func definition(for theme: AppTheme) -> ThemeDefinition {
        switch theme {
        case .glass: return .glass
        case .bento: return .bento
        case .film: return .film
        case .bar: return .bar
        case .noir: return .noir
        case .dataPaper: return .dataPaper
        case .ashVeil: return .ashVeil
        }
    }

    /// Default — instrument chrome + system glass.
    static let glass = ThemeDefinition(
        ui: .glass,
        background: .systemGlass,
        layout: .instrument
    )

    /// Bento — card grid + system glass.
    static let bento = ThemeDefinition(
        ui: .bento,
        background: .systemGlass,
        layout: .bento
    )

    /// Neon — neon console chrome over the warm light-field scene.
    static let film = ThemeDefinition(
        ui: .film,
        background: .sunGold,
        layout: .instrument
    )

    /// Night Bar — smoked-club chrome + red/green neon light field.
    static let bar = ThemeDefinition(
        ui: .bar,
        background: .bar,
        layout: .instrument
    )

    /// Ink Night — noir ink + cool light-field scene.
    static let noir = ThemeDefinition(
        ui: .noir,
        background: .inkNight,
        layout: .instrument
    )

    /// Data Paper — neutral ledger tokens + static technical grid.
    static let dataPaper = ThemeDefinition(
        ui: .dataPaper,
        background: .technicalPaper,
        layout: .instrument
    )

    /// Ash Veil — soft charcoal UI over a monochrome photo scene.
    static let ashVeil = ThemeDefinition(
        ui: .ashVeil,
        background: .ashVeil,
        layout: .instrument
    )
}
