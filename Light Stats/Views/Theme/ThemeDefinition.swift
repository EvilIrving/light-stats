//
//  ThemeDefinition.swift
//  Light Stats
//
//  Single composition table: AppTheme → UI + background + layout.
//  Five product presets are fixed here. Business views consume the resolved
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
        case .noir: return .noir
        case .dataPaper: return .dataPaper
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

    /// Sun Gold — film ink + warm light-field scene.
    static let film = ThemeDefinition(
        ui: .film,
        background: .sunGold,
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
}
