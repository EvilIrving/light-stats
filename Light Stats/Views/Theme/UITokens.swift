//
//  UITokens.swift
//  Light Stats
//
//  Resolved interface tokens. Views read these via `@Environment(\.theme)` —
//  never hard-code theme-specific colors in chrome, and never switch on
//  `AppTheme` to pick paint.
//
//  Background paint is routed by `BackgroundSceneID` through `BackgroundHost`.
//

import SwiftUI

/// Snapshot of interface paint. Value type, cheap to pass.
struct UITokens: Equatable {
    /// `nil` = follow system appearance.
    let preferredColorScheme: ColorScheme?

    let usesVibrantSurfaces: Bool

    // MARK: Surfaces (list rows / wells — not floating cards)

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

    // MARK: Signals (metric text, bars, health)

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

    // MARK: Preset paint (composed by ThemeDefinition)

    /// Sun Gold / 晒金 — dark reading surface + high-contrast cream ink.
    static let film = UITokens(
        preferredColorScheme: .dark,
        usesVibrantSurfaces: false,
        surfaceFill: Color(red: 0.14, green: 0.09, blue: 0.07).opacity(0.88),
        surfaceStroke: Color.white.opacity(0.14),
        surfaceShadowOpacity: 0.30,
        tabTrackFill: Color.white.opacity(0.10),
        tabSelectedFill: Color(red: 0.22, green: 0.14, blue: 0.11).opacity(0.96),
        rowHoverFill: Color.white.opacity(0.10),
        wellFill: Color.white.opacity(0.12),
        inkPrimary: Color(red: 1.0, green: 0.98, blue: 0.95),
        inkMuted: Color(red: 0.96, green: 0.92, blue: 0.88),
        inkSecondary: Color(red: 0.90, green: 0.84, blue: 0.78),
        inkFaint: Color(red: 0.78, green: 0.70, blue: 0.62),
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

    /// Original bento-grid product look — raised cards + classic metric greens.
    static let bento = UITokens(
        preferredColorScheme: nil,
        usesVibrantSurfaces: true,
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
    static let glass = UITokens(
        preferredColorScheme: nil,
        usesVibrantSurfaces: true,
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

    /// Near-black reading surface — strong white ink.
    static let noir = UITokens(
        preferredColorScheme: .dark,
        usesVibrantSurfaces: false,
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

    /// Data Paper — neutral technical sheet with restrained engineering signals.
    static let dataPaper = UITokens(
        preferredColorScheme: .light,
        usesVibrantSurfaces: false,
        surfaceFill: Color(red: 0.985, green: 0.990, blue: 0.995).opacity(0.92),
        surfaceStroke: Color(red: 0.58, green: 0.63, blue: 0.69).opacity(0.52),
        surfaceShadowOpacity: 0.02,
        tabTrackFill: Color.white.opacity(0.72),
        tabSelectedFill: Color.white.opacity(0.98),
        rowHoverFill: Color(red: 0.08, green: 0.14, blue: 0.20).opacity(0.06),
        wellFill: Color(red: 0.16, green: 0.22, blue: 0.28).opacity(0.10),
        inkPrimary: Color(red: 0.067, green: 0.078, blue: 0.094),
        inkMuted: Color(red: 0.18, green: 0.21, blue: 0.25),
        inkSecondary: Color(red: 0.30, green: 0.34, blue: 0.38),
        inkFaint: Color(red: 0.46, green: 0.51, blue: 0.56),
        signalGood: Color(red: 0.086, green: 0.514, blue: 0.357),
        signalWarn: Color(red: 0.663, green: 0.408, blue: 0.0),
        signalBad: Color(red: 0.80, green: 0.188, blue: 0.251),
        signalInfo: Color(red: 0.031, green: 0.486, blue: 0.569),
        signalAccent: Color(red: 0.886, green: 0.231, blue: 0.231),
        lineHairline: Color(red: 0.42, green: 0.47, blue: 0.53).opacity(0.38),
        chartLine: Color(red: 0.031, green: 0.486, blue: 0.569),
        dividerOpacity: 0.38,
        accent: Color(red: 0.886, green: 0.231, blue: 0.231)
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
