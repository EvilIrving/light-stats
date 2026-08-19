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
    let chromeStyle: ThemeChromeStyle

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
    /// Neutral glyph color for metric icons; separate from semantic status colors.
    let metricIcon: Color

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
    /// Default stroke for single-series sparklines.
    let chartLine: Color
    /// Contrasting stroke for the second series in comparative charts.
    let chartSecondary: Color
    let dividerOpacity: Double
    let accent: Color

    // MARK: Back-compat aliases

    var cardFill: Color { surfaceFill }
    var cardStroke: Color { surfaceStroke }
    var cardShadowOpacity: Double { surfaceShadowOpacity }

    // MARK: Preset paint (composed by ThemeDefinition)

    /// Golden Hour — luminous instrument ink over the full Sun Gold light field.
    /// No content plate and no glow: contrast comes from bright ink against the scene.
    static let film = UITokens(
        preferredColorScheme: .dark,
        chromeStyle: .neon,
        usesVibrantSurfaces: false,
        surfaceFill: .clear,
        surfaceStroke: Color(red: 0.85, green: 0.75, blue: 0.58).opacity(0.36),
        surfaceShadowOpacity: 0,
        tabTrackFill: Color(red: 0.16, green: 0.045, blue: 0.008).opacity(0.20),
        tabSelectedFill: Color(red: 1.0, green: 0.82, blue: 0.58).opacity(0.09),
        rowHoverFill: Color(red: 1.0, green: 0.77, blue: 0.54).opacity(0.12),
        wellFill: Color(red: 0.12, green: 0.025, blue: 0.004).opacity(0.58),
        inkPrimary: Color(red: 1.0, green: 0.973, blue: 0.918),
        inkMuted: Color(red: 0.945, green: 0.890, blue: 0.812),
        inkSecondary: Color(red: 0.867, green: 0.784, blue: 0.678),
        inkFaint: Color(red: 0.773, green: 0.686, blue: 0.573),
        metricIcon: Color(red: 0.663, green: 0.847, blue: 0.871),
        signalGood: Color(red: 0.718, green: 0.906, blue: 0.690),
        signalWarn: Color(red: 1.0, green: 0.835, blue: 0.416),
        signalBad: Color(red: 1.0, green: 0.569, blue: 0.533),
        signalInfo: Color(red: 0.522, green: 0.902, blue: 0.949),
        signalAccent: Color(red: 1.0, green: 0.773, blue: 0.541),
        lineHairline: Color(red: 0.847, green: 0.745, blue: 0.580).opacity(0.30),
        chartLine: Color(red: 0.522, green: 0.902, blue: 0.949),
        chartSecondary: Color(red: 0.780, green: 0.725, blue: 1.0),
        dividerOpacity: 0.22,
        accent: Color(red: 1.0, green: 0.878, blue: 0.627)
    )

    /// Amber / 琥珀 — espresso-black cocktail bar lit by warm amber
    /// bar light with a single cool teal neon accent. Red survives only as
    /// the semantic “critical” status color, never as decor.
    static let bar = UITokens(
        preferredColorScheme: .dark,
        chromeStyle: .nightBar,
        usesVibrantSurfaces: false,
        surfaceFill: Color(red: 0.052, green: 0.038, blue: 0.030).opacity(0.78),
        surfaceStroke: Color(red: 1.0, green: 0.70, blue: 0.38).opacity(0.26),
        surfaceShadowOpacity: 0.38,
        tabTrackFill: Color.clear,
        tabSelectedFill: Color.clear,
        rowHoverFill: Color(red: 1.0, green: 0.66, blue: 0.30).opacity(0.12),
        wellFill: Color(red: 0.012, green: 0.085, blue: 0.078).opacity(0.55),
        inkPrimary: Color(red: 1.0, green: 0.968, blue: 0.928),
        inkMuted: Color(red: 0.95, green: 0.89, blue: 0.83),
        inkSecondary: Color(red: 0.82, green: 0.75, blue: 0.68),
        inkFaint: Color(red: 0.62, green: 0.55, blue: 0.49),
        metricIcon: Color(red: 1.0, green: 0.66, blue: 0.34),
        signalGood: Color(red: 0.22, green: 0.86, blue: 0.78),
        signalWarn: Color(red: 1.0, green: 0.74, blue: 0.30),
        signalBad: Color(red: 1.0, green: 0.42, blue: 0.48),
        signalInfo: Color(red: 0.44, green: 0.86, blue: 1.0),
        signalAccent: Color(red: 1.0, green: 0.60, blue: 0.28),
        lineHairline: Color(red: 1.0, green: 0.70, blue: 0.38).opacity(0.20),
        chartLine: Color(red: 0.22, green: 0.86, blue: 0.78),
        chartSecondary: Color(red: 1.0, green: 0.64, blue: 0.32),
        dividerOpacity: 0.24,
        accent: Color(red: 1.0, green: 0.72, blue: 0.36)
    )

    /// System glass / vibrancy — instrument readout.
    static let glass = UITokens(
        preferredColorScheme: nil,
        chromeStyle: .standard,
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
        metricIcon: Color.secondary,
        signalGood: Color(red: 0.20, green: 0.72, blue: 0.38),
        signalWarn: Color(red: 0.92, green: 0.72, blue: 0.12),
        signalBad: Color(red: 0.90, green: 0.28, blue: 0.24),
        signalInfo: Color(red: 0.12, green: 0.62, blue: 0.78),
        signalAccent: Color(red: 0.95, green: 0.52, blue: 0.18),
        lineHairline: Color.primary.opacity(0.10),
        chartLine: Color(red: 0.20, green: 0.72, blue: 0.38),
        chartSecondary: Color(red: 0.12, green: 0.62, blue: 0.78),
        dividerOpacity: 0.08,
        accent: Color.accentColor
    )

    /// Near-black reading surface — strong white ink.
    static let noir = UITokens(
        preferredColorScheme: .dark,
        chromeStyle: .standard,
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
        metricIcon: Color.white.opacity(0.78),
        signalGood: Color(red: 0.38, green: 0.96, blue: 0.72),
        signalWarn: Color(red: 1.0, green: 0.86, blue: 0.42),
        signalBad: Color(red: 1.0, green: 0.42, blue: 0.48),
        signalInfo: Color(red: 0.48, green: 0.78, blue: 1.0),
        signalAccent: Color(red: 0.78, green: 0.62, blue: 1.0),
        lineHairline: Color.white.opacity(0.16),
        chartLine: Color(red: 0.50, green: 0.82, blue: 1.0),
        chartSecondary: Color(red: 0.78, green: 0.62, blue: 1.0),
        dividerOpacity: 0.18,
        accent: Color(red: 0.72, green: 0.78, blue: 1.0)
    )

    /// Data Paper — neutral technical sheet with restrained engineering signals.
    static let dataPaper = UITokens(
        preferredColorScheme: .light,
        chromeStyle: .standard,
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
        metricIcon: Color(red: 0.30, green: 0.34, blue: 0.38),
        signalGood: Color(red: 0.086, green: 0.514, blue: 0.357),
        signalWarn: Color(red: 0.663, green: 0.408, blue: 0.0),
        signalBad: Color(red: 0.80, green: 0.188, blue: 0.251),
        signalInfo: Color(red: 0.031, green: 0.486, blue: 0.569),
        signalAccent: Color(red: 0.886, green: 0.231, blue: 0.231),
        lineHairline: Color(red: 0.42, green: 0.47, blue: 0.53).opacity(0.38),
        chartLine: Color(red: 0.031, green: 0.486, blue: 0.569),
        chartSecondary: Color(red: 0.886, green: 0.231, blue: 0.231),
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
