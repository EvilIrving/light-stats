//
//  ThemeTokens.swift
//  Light Stats
//
//  Resolved color / material tokens for a single AppTheme. Views read these via
//  `@Environment(\.theme)` — never hard-code theme-specific colors in chrome.
//
//  Mesh themes (film / noir) pair a decorative light field with a content scrim
//  so ink always meets WCAG-ish contrast on a stable dark reading surface.
//

import SwiftUI

/// Snapshot of paint tokens for the active theme. Value type, cheap to pass.
struct ThemeTokens: Equatable {
    let theme: AppTheme

    /// `nil` = follow system appearance (glass only).
    let preferredColorScheme: ColorScheme?

    // MARK: Background strategy

    let usesGlass: Bool
    let usesMesh: Bool
    let grainOpacity: Double

    let canvas: Color
    let meshBase: Color
    let meshBlobPrimary: Color
    let meshBlobSecondary: Color
    let meshBlobHighlight: Color

    /// Drawn *above* the mesh / glass, *under* UI content. Clear for glass.
    /// Gives text a stable dark field while mesh still shows at the edges.
    let contentScrim: Color

    // MARK: Surfaces (list rows / wells — not floating cards)

    let surfaceFill: Color
    let surfaceStroke: Color
    let surfaceShadowOpacity: Double
    let tabTrackFill: Color
    let tabSelectedFill: Color
    let rowHoverFill: Color
    let wellFill: Color

    // MARK: Ink (must stay readable on contentScrim + residual mesh glow)

    let inkPrimary: Color
    let inkMuted: Color
    let inkSecondary: Color
    let inkFaint: Color

    // MARK: Signals (metric text, bars, health — fully theme-specific)

    /// Healthy / low pressure (historically “green”).
    let signalGood: Color
    /// Caution / mid pressure.
    let signalWarn: Color
    /// Critical / high pressure.
    let signalBad: Color
    /// Secondary series (e.g. network down).
    let signalInfo: Color
    /// Primary series / warm accent (e.g. network up, battery mid).
    let signalAccent: Color

    // MARK: Chrome

    /// Hairline rules between sections.
    let lineHairline: Color
    /// Default stroke for sparklines when a series doesn’t supply its own tint.
    let chartLine: Color
    let dividerOpacity: Double
    let accent: Color

    // MARK: Back-compat aliases

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

    /// 胶片棕 — warm mesh atmosphere + dark reading scrim + high-contrast cream ink.
    static let film = ThemeTokens(
        theme: .film,
        preferredColorScheme: .dark,
        usesGlass: false,
        usesMesh: true,
        // Shared grit strength with noir — only warmth tint differs in GrainTextureView.
        grainOpacity: 0.32,
        canvas: Color(red: 0.10, green: 0.06, blue: 0.05),
        // Darker base so residual mesh glow doesn’t wash ink.
        meshBase: Color(red: 0.16, green: 0.08, blue: 0.07),
        meshBlobPrimary: Color(red: 0.42, green: 0.20, blue: 0.18),
        meshBlobSecondary: Color(red: 0.78, green: 0.40, blue: 0.30),
        meshBlobHighlight: Color(red: 0.90, green: 0.72, blue: 0.58),
        // External full-frame scrim disabled — reading veil lives inside mesh bg.
        contentScrim: .clear,
        surfaceFill: Color(red: 0.14, green: 0.09, blue: 0.07).opacity(0.88),
        surfaceStroke: Color.white.opacity(0.14),
        surfaceShadowOpacity: 0.30,
        tabTrackFill: Color.white.opacity(0.10),
        tabSelectedFill: Color(red: 0.22, green: 0.14, blue: 0.11).opacity(0.96),
        rowHoverFill: Color.white.opacity(0.10),
        wellFill: Color.white.opacity(0.12),
        // Near-white cream ink — high contrast on dark scrim.
        inkPrimary: Color(red: 1.0, green: 0.98, blue: 0.95),
        inkMuted: Color(red: 0.96, green: 0.92, blue: 0.88),
        inkSecondary: Color(red: 0.90, green: 0.84, blue: 0.78),
        inkFaint: Color(red: 0.78, green: 0.70, blue: 0.62),
        // Warm film “live” ramp — gold-sage / amber / coral (not system green).
        signalGood: Color(red: 0.82, green: 0.90, blue: 0.48),
        signalWarn: Color(red: 1.0, green: 0.78, blue: 0.38),
        signalBad: Color(red: 1.0, green: 0.48, blue: 0.40),
        signalInfo: Color(red: 0.72, green: 0.88, blue: 0.92),
        signalAccent: Color(red: 1.0, green: 0.62, blue: 0.38),
        lineHairline: Color(red: 0.96, green: 0.82, blue: 0.68).opacity(0.22),
        chartLine: Color(red: 0.90, green: 0.78, blue: 0.48),
        dividerOpacity: 0.20,
        accent: Color(red: 1.0, green: 0.68, blue: 0.48)
    )

    /// Original bento-grid product look — glass + raised cards + classic metric greens.
    static let bento = ThemeTokens(
        theme: .bento,
        preferredColorScheme: nil,
        usesGlass: true,
        usesMesh: false,
        grainOpacity: 0,
        canvas: Color(nsColor: .windowBackgroundColor),
        meshBase: .clear,
        meshBlobPrimary: .clear,
        meshBlobSecondary: .clear,
        meshBlobHighlight: .clear,
        contentScrim: .clear,
        // Matches the pre-redesign BentoCard fill.
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

    /// System glass / vibrancy — instrument readout (no bento card chrome).
    static let glass = ThemeTokens(
        theme: .glass,
        preferredColorScheme: nil,
        usesGlass: true,
        usesMesh: false,
        grainOpacity: 0,
        canvas: Color(nsColor: .windowBackgroundColor),
        meshBase: .clear,
        meshBlobPrimary: .clear,
        meshBlobSecondary: .clear,
        meshBlobHighlight: .clear,
        contentScrim: .clear,
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

    /// Near-black grain — cool mesh + strong white ink.
    static let noir = ThemeTokens(
        theme: .noir,
        preferredColorScheme: .dark,
        usesGlass: false,
        usesMesh: true,
        // Match film grainOpacity so fine/body grit reads the same.
        grainOpacity: 0.32,
        canvas: Color(red: 0.03, green: 0.03, blue: 0.04),
        meshBase: Color(red: 0.04, green: 0.04, blue: 0.06),
        meshBlobPrimary: Color(red: 0.10, green: 0.10, blue: 0.15),
        meshBlobSecondary: Color(red: 0.22, green: 0.22, blue: 0.36),
        meshBlobHighlight: Color(red: 0.48, green: 0.52, blue: 0.68),
        contentScrim: .clear,
        surfaceFill: Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.90),
        surfaceStroke: Color.white.opacity(0.14),
        surfaceShadowOpacity: 0.32,
        tabTrackFill: Color.white.opacity(0.10),
        tabSelectedFill: Color(red: 0.18, green: 0.18, blue: 0.22),
        rowHoverFill: Color.white.opacity(0.10),
        wellFill: Color.white.opacity(0.12),
        inkPrimary: Color.white,
        inkMuted: Color.white.opacity(0.92),
        inkSecondary: Color.white.opacity(0.78),
        inkFaint: Color.white.opacity(0.58),
        // Cool mint / ice / violet ramp — distinct from film gold-sage.
        signalGood: Color(red: 0.38, green: 0.96, blue: 0.72),
        signalWarn: Color(red: 1.0, green: 0.86, blue: 0.42),
        signalBad: Color(red: 1.0, green: 0.42, blue: 0.48),
        signalInfo: Color(red: 0.48, green: 0.78, blue: 1.0),
        signalAccent: Color(red: 0.78, green: 0.62, blue: 1.0),
        lineHairline: Color.white.opacity(0.16),
        chartLine: Color(red: 0.50, green: 0.82, blue: 1.0),
        dividerOpacity: 0.18,
        accent: Color(red: 0.72, green: 0.78, blue: 1.0)
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
