//
//  BackgroundConfiguration.swift
//  Light Stats
//
//  Resolved backdrop capability. `ThemeBackgroundView` reads only this type.
//

import SwiftUI

enum BackgroundKind: String, Equatable, Sendable {
    case glass
    case mesh
    case solid
}

/// Independent mesh painter. Not an `AppTheme` case.
enum MeshRendererKind: String, Equatable, Sendable {
    case film
    case noir
}

/// Which persisted grain / flow knobs a mesh background uses.
enum MeshAppearanceSlot: String, Equatable, Sendable {
    case film
    case noir
}

/// Quasi-periodic Lissajous orbit baked into a mesh background.
struct MeshMotionConfiguration: Equatable, Sendable {
    let amplitudeBase: CGFloat
    let amplitudeSpan: CGFloat
    let phaseOffset: CGFloat
    let horizontalPrimary: CGFloat
    let horizontalSecondary: CGFloat
    let verticalPrimary: CGFloat
    let verticalSecondary: CGFloat

    static let film = MeshMotionConfiguration(
        amplitudeBase: 0.68,
        amplitudeSpan: 0.32,
        phaseOffset: 0.45,
        horizontalPrimary: 0.105,
        horizontalSecondary: 0.038,
        verticalPrimary: 0.065,
        verticalSecondary: 0.028
    )

    static let noir = MeshMotionConfiguration(
        amplitudeBase: 0.35,
        amplitudeSpan: 1.15,
        phaseOffset: 1.35,
        horizontalPrimary: 0.14,
        horizontalSecondary: 0.05,
        verticalPrimary: 0.12,
        verticalSecondary: 0.045
    )

    static let idle = MeshMotionConfiguration(
        amplitudeBase: 0,
        amplitudeSpan: 0,
        phaseOffset: 0,
        horizontalPrimary: 0,
        horizontalSecondary: 0,
        verticalPrimary: 0,
        verticalSecondary: 0
    )
}

/// Snapshot of backdrop paint and renderer choice. Value type, cheap to pass.
struct BackgroundConfiguration: Equatable {
    let kind: BackgroundKind
    let meshRenderer: MeshRendererKind?
    let appearanceSlot: MeshAppearanceSlot?

    let grainOpacity: Double
    let grainWarmth: Double
    let veilCenter: Color
    let motion: MeshMotionConfiguration

    let canvas: Color
    let meshBase: Color
    let meshBlobPrimary: Color
    let meshBlobSecondary: Color
    let meshBlobHighlight: Color

    /// Drawn *above* the mesh / glass, *under* UI content. Clear for glass.
    let contentScrim: Color

    /// System vibrancy — no mesh art.
    static let glass = BackgroundConfiguration(
        kind: .glass,
        meshRenderer: nil,
        appearanceSlot: nil,
        grainOpacity: 0,
        grainWarmth: 0,
        veilCenter: .clear,
        motion: .idle,
        canvas: Color(nsColor: .windowBackgroundColor),
        meshBase: .clear,
        meshBlobPrimary: .clear,
        meshBlobSecondary: .clear,
        meshBlobHighlight: .clear,
        contentScrim: .clear
    )

    /// Sun Gold / 晒金 — warm mesh atmosphere + S-curve light field.
    static let film = BackgroundConfiguration(
        kind: .mesh,
        meshRenderer: .film,
        appearanceSlot: .film,
        grainOpacity: 0.32,
        grainWarmth: 0.5,
        veilCenter: Color(red: 0.06, green: 0.03, blue: 0.02),
        motion: .film,
        canvas: Color(red: 0.10, green: 0.06, blue: 0.05),
        meshBase: Color(red: 0.16, green: 0.08, blue: 0.07),
        meshBlobPrimary: Color(red: 0.42, green: 0.20, blue: 0.18),
        meshBlobSecondary: Color(red: 0.78, green: 0.40, blue: 0.30),
        meshBlobHighlight: Color(red: 0.90, green: 0.72, blue: 0.58),
        contentScrim: .clear
    )

    /// Ink Night — cool mesh atmosphere + vertical shaft light field.
    static let noir = BackgroundConfiguration(
        kind: .mesh,
        meshRenderer: .noir,
        appearanceSlot: .noir,
        grainOpacity: 0.32,
        grainWarmth: 0,
        veilCenter: .black,
        motion: .noir,
        canvas: Color(red: 0.03, green: 0.03, blue: 0.04),
        meshBase: Color(red: 0.04, green: 0.04, blue: 0.06),
        meshBlobPrimary: Color(red: 0.10, green: 0.10, blue: 0.15),
        meshBlobSecondary: Color(red: 0.22, green: 0.22, blue: 0.36),
        meshBlobHighlight: Color(red: 0.48, green: 0.52, blue: 0.68),
        contentScrim: .clear
    )
}
