//
//  ThemeTokens.swift
//  Light Stats
//
//  Resolved paint tokens for a single AppTheme. Views read these through
//  `@Environment(\.theme)` and never hard-code theme-specific chrome colors.
//

import SwiftUI

/// Snapshot of paint tokens for the active theme. Value type, cheap to pass.
struct ThemeTokens: Equatable {
    let theme: AppTheme

    /// `nil` follows the system appearance for native glass themes.
    let preferredColorScheme: ColorScheme?

    // MARK: Background artwork

    let usesGlass: Bool
    let usesStaticArtwork: Bool
    let textureOpacity: Double
    let canvas: Color
    let artworkShadow: Color
    let artworkMidtone: Color
    let artworkGlow: Color

    // MARK: Surfaces

    let surfaceFill: Color
    let surfaceStroke: Color
    let surfaceShadowOpacity: Double
    let tabTrackFill: Color
    let tabSelectedFill: Color
    let rowHoverFill: Color
    let wellFill: Color

    // MARK: Ink

    let inkPrimary: Color
    let inkMuted: Color
    let inkSecondary: Color
    let inkFaint: Color

    // MARK: Signals

    /// Healthy or low pressure.
    let signalGood: Color
    /// Caution or medium pressure.
    let signalWarn: Color
    /// Critical or high pressure.
    let signalBad: Color
    /// Secondary series, such as network download.
    let signalInfo: Color
    /// Primary series, such as network upload.
    let signalAccent: Color

    // MARK: Chrome

    let lineHairline: Color
    let chartLine: Color
    let dividerOpacity: Double
    let accent: Color

    // MARK: Backward-compatible aliases

    var cardFill: Color { surfaceFill }
    var cardStroke: Color { surfaceStroke }
    var cardShadowOpacity: Double { surfaceShadowOpacity }

    // MARK: Factories

    static func tokens(for theme: AppTheme) -> ThemeTokens {
        switch theme {
        case .film: return .film
        case .bento: return .bento
        case .glass: return .glass
        case .noir: return .noir
        }
    }

    /// Sun Gold: a static ivory, dusty-rose, and coral tonal field.
    static let film = ThemeTokens(
        theme: .film,
        preferredColorScheme: .light,
        usesGlass: false,
        usesStaticArtwork: true,
        textureOpacity: 0.10,
        canvas: Color(red: 0.91, green: 0.77, blue: 0.72),
        artworkShadow: Color(red: 0.42, green: 0.23, blue: 0.25),
        artworkMidtone: Color(red: 0.64, green: 0.36, blue: 0.36),
        artworkGlow: Color(red: 0.99, green: 0.93, blue: 0.89),
        surfaceFill: Color(red: 0.99, green: 0.94, blue: 0.90).opacity(0.44),
        surfaceStroke: Color(red: 0.27, green: 0.14, blue: 0.15).opacity(0.13),
        surfaceShadowOpacity: 0.08,
        tabTrackFill: Color(red: 0.25, green: 0.13, blue: 0.14).opacity(0.07),
        tabSelectedFill: Color(red: 0.99, green: 0.94, blue: 0.90).opacity(0.72),
        rowHoverFill: Color(red: 0.99, green: 0.94, blue: 0.90).opacity(0.34),
        wellFill: Color(red: 0.27, green: 0.14, blue: 0.15).opacity(0.07),
        inkPrimary: Color(red: 0.16, green: 0.075, blue: 0.085),
        inkMuted: Color(red: 0.24, green: 0.13, blue: 0.14),
        inkSecondary: Color(red: 0.34, green: 0.22, blue: 0.22),
        inkFaint: Color(red: 0.46, green: 0.33, blue: 0.32),
        signalGood: Color(red: 0.31, green: 0.43, blue: 0.13),
        signalWarn: Color(red: 0.66, green: 0.39, blue: 0.06),
        signalBad: Color(red: 0.72, green: 0.20, blue: 0.17),
        signalInfo: Color(red: 0.22, green: 0.42, blue: 0.48),
        signalAccent: Color(red: 0.74, green: 0.28, blue: 0.18),
        lineHairline: Color(red: 0.27, green: 0.14, blue: 0.15).opacity(0.13),
        chartLine: Color(red: 0.43, green: 0.49, blue: 0.18),
        dividerOpacity: 0.12,
        accent: Color(red: 0.65, green: 0.22, blue: 0.16)
    )

    /// Original bento-grid product look with raised cards and classic signals.
    static let bento = ThemeTokens(
        theme: .bento,
        preferredColorScheme: nil,
        usesGlass: true,
        usesStaticArtwork: false,
        textureOpacity: 0,
        canvas: Color(nsColor: .windowBackgroundColor),
        artworkShadow: .clear,
        artworkMidtone: .clear,
        artworkGlow: .clear,
        surfaceFill: Color(nsColor: .controlBackgroundColor).opacity(0.78),
        surfaceStroke: Color.primary.opacity(0.08),
        surfaceShadowOpacity: 0.06,
        tabTrackFill: Color.primary.opacity(0.03),
        tabSelectedFill: Color(nsColor: .controlBackgroundColor),
        rowHoverFill: Color.primary.opacity(0.06),
        wellFill: Color.primary.opacity(0.05),
        inkPrimary: Color.primary,
        inkMuted: Color.primary.opacity(0.9),
        inkSecondary: Color.secondary,
        inkFaint: Color(nsColor: .tertiaryLabelColor),
        signalGood: .green,
        signalWarn: .yellow,
        signalBad: .red,
        signalInfo: .cyan,
        signalAccent: .orange,
        lineHairline: Color.primary.opacity(0.08),
        chartLine: .green,
        dividerOpacity: 0.08,
        accent: Color.accentColor
    )

    /// System glass or vibrancy with the continuous instrument layout.
    static let glass = ThemeTokens(
        theme: .glass,
        preferredColorScheme: nil,
        usesGlass: true,
        usesStaticArtwork: false,
        textureOpacity: 0,
        canvas: Color(nsColor: .windowBackgroundColor),
        artworkShadow: .clear,
        artworkMidtone: .clear,
        artworkGlow: .clear,
        surfaceFill: Color(nsColor: .controlBackgroundColor).opacity(0.55),
        surfaceStroke: Color.primary.opacity(0.08),
        surfaceShadowOpacity: 0.04,
        tabTrackFill: Color.primary.opacity(0.03),
        tabSelectedFill: Color(nsColor: .controlBackgroundColor),
        rowHoverFill: Color.primary.opacity(0.06),
        wellFill: Color.primary.opacity(0.05),
        inkPrimary: Color.primary,
        inkMuted: Color.primary.opacity(0.9),
        inkSecondary: Color.secondary,
        inkFaint: Color(nsColor: .tertiaryLabelColor),
        signalGood: Color(red: 0.20, green: 0.72, blue: 0.38),
        signalWarn: Color(red: 0.92, green: 0.72, blue: 0.12),
        signalBad: Color(red: 0.90, green: 0.28, blue: 0.24),
        signalInfo: Color(red: 0.12, green: 0.62, blue: 0.78),
        signalAccent: Color(red: 0.95, green: 0.52, blue: 0.18),
        lineHairline: Color.primary.opacity(0.10),
        chartLine: Color(red: 0.20, green: 0.72, blue: 0.38),
        dividerOpacity: 0.08,
        accent: Color.accentColor
    )

    /// Ink Night: an almost-black field with a restrained neutral graphite bloom.
    static let noir = ThemeTokens(
        theme: .noir,
        preferredColorScheme: .dark,
        usesGlass: false,
        usesStaticArtwork: true,
        textureOpacity: 0.035,
        canvas: Color(red: 0.024, green: 0.026, blue: 0.026),
        artworkShadow: Color(red: 0.01, green: 0.011, blue: 0.011),
        artworkMidtone: Color(red: 0.20, green: 0.205, blue: 0.205),
        artworkGlow: Color(red: 0.36, green: 0.365, blue: 0.355),
        surfaceFill: Color(red: 0.065, green: 0.07, blue: 0.07).opacity(0.78),
        surfaceStroke: Color.white.opacity(0.10),
        surfaceShadowOpacity: 0.20,
        tabTrackFill: Color.white.opacity(0.055),
        tabSelectedFill: Color(red: 0.14, green: 0.145, blue: 0.145).opacity(0.88),
        rowHoverFill: Color.white.opacity(0.065),
        wellFill: Color.white.opacity(0.075),
        inkPrimary: Color(red: 0.95, green: 0.945, blue: 0.925),
        inkMuted: Color(red: 0.84, green: 0.835, blue: 0.815),
        inkSecondary: Color(red: 0.69, green: 0.69, blue: 0.67),
        inkFaint: Color(red: 0.47, green: 0.475, blue: 0.46),
        signalGood: Color(red: 0.66, green: 0.79, blue: 0.55),
        signalWarn: Color(red: 0.84, green: 0.68, blue: 0.43),
        signalBad: Color(red: 0.84, green: 0.46, blue: 0.43),
        signalInfo: Color(red: 0.54, green: 0.68, blue: 0.72),
        signalAccent: Color(red: 0.70, green: 0.60, blue: 0.54),
        lineHairline: Color.white.opacity(0.10),
        chartLine: Color(red: 0.68, green: 0.73, blue: 0.69),
        dividerOpacity: 0.10,
        accent: Color(red: 0.82, green: 0.81, blue: 0.77)
    )

    // MARK: Metric ramp

    func colorForUsage(_ usage: Double) -> Color {
        if usage < 50 {
            return signalGood
        } else if usage < 80 {
            return signalWarn
        } else {
            return signalBad
        }
    }
}
