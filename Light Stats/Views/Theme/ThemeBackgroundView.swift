//
//  ThemeBackgroundView.swift
//  Light Stats
//
//  Mesh stack (bottom → top):
//    1. Light field (film S-curve vs noir vertical shaft) — bold enough to read
//    2. Soft radial reading veil (center only) — text contrast without burying art
//    3. Shared film grain — always on top so grit stays visible
//
//  Do NOT paint a full-frame opaque scrim over this; it kills grain + light shapes.
//

import SwiftUI

struct ThemeBackgroundView: View {
    let tokens: ThemeTokens
    var cornerRadius: CGFloat = 12
    var configuresWindow: Bool = false
    var fallbackMaterial: NSVisualEffectView.Material = .sidebar

    var body: some View {
        Group {
            if tokens.usesGlass {
                GlassBackgroundView(
                    cornerRadius: cornerRadius,
                    fallbackMaterial: fallbackMaterial,
                    configuresWindow: configuresWindow
                )
            } else if tokens.usesMesh {
                FluidMeshBackground(tokens: tokens)
            } else {
                tokens.canvas
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Mesh shell

private struct FluidMeshBackground: View {
    let tokens: ThemeTokens

    /// Same grit strength for film + noir; film only warms the tint.
    private var grainWarmth: Double { tokens.theme == .film ? 0.5 : 0 }
    private var grainOpacity: Double { 0.42 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let period = tokens.theme == .noir ? 24.0 : 18.0
            let phase = CGFloat((time / period).truncatingRemainder(dividingBy: 1.0) * .pi * 2)

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let scale = min(width, height)

                ZStack {
                    // 1) Light art — flattened for blur cost.
                    Group {
                        switch tokens.theme {
                        case .film:
                            FilmLightField(
                                tokens: tokens, width: width, height: height, scale: scale, phase: phase
                            )
                        case .noir:
                            NoirLightField(
                                tokens: tokens, width: width, height: height, scale: scale, phase: phase
                            )
                        default:
                            tokens.meshBase
                        }
                    }
                    .drawingGroup(opaque: true, colorMode: .extendedLinear)

                    // 2) Soft center darken only — edges keep full light + shape.
                    readingVeil(width: width, height: height, scale: scale)

                    // 3) Grain always on top — must stay outside drawingGroup.
                    GrainTextureView(opacity: grainOpacity, warmth: grainWarmth)
                }
                .frame(width: width, height: height)
            }
        }
    }

    /// Center opacity ~0.4 so cream text holds; rim almost clear so ribbons read.
    private func readingVeil(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        let center = tokens.theme == .film
            ? Color(red: 0.06, green: 0.03, blue: 0.02)
            : Color.black

        return RadialGradient(
            colors: [
                center.opacity(0.52),
                center.opacity(0.28),
                center.opacity(0.08),
                Color.clear
            ],
            center: UnitPoint(x: 0.5, y: 0.48),
            startRadius: scale * 0.08,
            endRadius: max(width, height) * 0.72
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Film: warm diagonal S-curve (bold)

private struct FilmLightField: View {
    let tokens: ThemeTokens
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let phase: CGFloat

    var body: some View {
        let driftX = cos(phase) * width * 0.07
        let driftY = sin(phase * 0.75) * height * 0.04
        let driftX2 = cos(phase * 0.95 + 1.1) * width * 0.055
        let driftY2 = sin(phase * 1.05 + 0.5) * height * 0.045

        return ZStack {
            tokens.meshBase

            // Full diagonal wash — cream → coral → burgundy.
            LinearGradient(
                colors: [
                    tokens.meshBlobHighlight.opacity(0.70),
                    tokens.meshBlobSecondary.opacity(0.55),
                    tokens.meshBlobPrimary.opacity(0.65),
                    tokens.meshBase
                ],
                startPoint: UnitPoint(x: 0.0 + cos(phase) * 0.05, y: 0.0),
                endPoint: UnitPoint(x: 1.0, y: 1.0)
            )

            // Coral mass (lower-right lobe of the S).
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            tokens.meshBlobSecondary.opacity(0.95),
                            tokens.meshBlobSecondary.opacity(0.55),
                            tokens.meshBlobPrimary.opacity(0.25),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.65, y: 0.6),
                        startRadius: 0,
                        endRadius: scale * 0.9
                    )
                )
                .frame(width: width * 1.7, height: height * 1.25)
                .blur(radius: scale * 0.2)
                .offset(x: width * 0.22 + driftX, y: height * 0.2 + driftY)
                .blendMode(.plusLighter)

            // Burgundy counter-lobe — secondary mass, kept soft so main ribbon reads.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            tokens.meshBlobPrimary.opacity(0.55),
                            tokens.meshBlobPrimary.opacity(0.22),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: scale * 0.75
                    )
                )
                .frame(width: width * 1.2, height: height * 0.9)
                .blur(radius: scale * 0.2)
                .offset(x: -width * 0.22 + driftX * 0.45, y: -height * 0.1 - driftY * 0.35)
                .blendMode(.normal)
                .opacity(0.55)

            // Primary S-ribbon — long shallow band (main light shape).
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            tokens.meshBlobHighlight.opacity(0.85),
                            tokens.meshBlobSecondary.opacity(0.75),
                            tokens.meshBlobHighlight.opacity(0.45),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * 1.85, height: height * 0.38)
                .blur(radius: scale * 0.09)
                .rotationEffect(.degrees(-26 + Double(sin(phase)) * 6))
                .offset(x: driftX * 0.8, y: height * 0.04 + driftY * 0.7)
                .blendMode(.screen)

            // Secondary ribbon — much quieter parallel accent.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            tokens.meshBlobSecondary.opacity(0.28),
                            tokens.meshBlobHighlight.opacity(0.16),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * 1.35, height: height * 0.16)
                .blur(radius: scale * 0.13)
                .rotationEffect(.degrees(-16 + Double(cos(phase * 0.85)) * 4))
                .offset(x: -width * 0.06 + driftX2, y: -height * 0.14 + driftY2)
                .blendMode(.screen)
                .opacity(0.4)

            // Cream bloom — secondary blob, reduced so it doesn’t compete with the ribbon.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tokens.meshBlobHighlight.opacity(0.32),
                            tokens.meshBlobHighlight.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: scale * 0.55
                    )
                )
                .frame(width: width * 0.85, height: height * 0.65)
                .blur(radius: scale * 0.16)
                .offset(x: -width * 0.32 + driftX2 * 0.4, y: -height * 0.32 + driftY2 * 0.3)
                .blendMode(.plusLighter)
                .opacity(0.45)
        }
    }
}

// MARK: - Noir: cool vertical shaft (bold, different geometry)

private struct NoirLightField: View {
    let tokens: ThemeTokens
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let phase: CGFloat

    var body: some View {
        let driftX = sin(phase * 0.9) * width * 0.04
        let driftY = cos(phase) * height * 0.065
        let driftX2 = cos(phase * 1.1 + 0.5) * width * 0.05
        let driftY2 = sin(phase * 0.7 + 1.0) * height * 0.05

        return ZStack {
            tokens.meshBase

            // Cool ceiling → void floor.
            LinearGradient(
                colors: [
                    tokens.meshBlobHighlight.opacity(0.45),
                    tokens.meshBlobSecondary.opacity(0.35),
                    tokens.meshBlobPrimary.opacity(0.5),
                    tokens.meshBase
                ],
                startPoint: UnitPoint(x: 0.5 + sin(phase) * 0.04, y: 0.0),
                endPoint: UnitPoint(x: 0.5, y: 1.0)
            )

            // Tall vertical shaft (center-right).
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            tokens.meshBlobHighlight.opacity(0.85),
                            tokens.meshBlobSecondary.opacity(0.55),
                            tokens.meshBlobPrimary.opacity(0.2),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.3),
                        startRadius: 0,
                        endRadius: scale * 0.95
                    )
                )
                .frame(width: width * 1.05, height: height * 1.7)
                .blur(radius: scale * 0.16)
                .offset(x: width * 0.14 + driftX, y: -height * 0.1 + driftY)
                .blendMode(.screen)

            // Cool side pool — secondary blob, quiet fill only.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            tokens.meshBlobSecondary.opacity(0.32),
                            tokens.meshBlobPrimary.opacity(0.18),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: scale * 0.7
                    )
                )
                .frame(width: width * 1.05, height: height * 0.8)
                .blur(radius: scale * 0.2)
                .offset(x: -width * 0.26 + driftX2, y: height * 0.24 + driftY2)
                .blendMode(.plusLighter)
                .opacity(0.4)

            // Steep ribbon A — main noir light band.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            tokens.meshBlobHighlight.opacity(0.8),
                            tokens.meshBlobSecondary.opacity(0.55),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width * 0.48, height: height * 1.65)
                .blur(radius: scale * 0.1)
                .rotationEffect(.degrees(14 + Double(sin(phase)) * 5))
                .offset(x: width * 0.1 + driftX * 0.5, y: driftY * 0.35)
                .blendMode(.screen)

            // Steep ribbon B — secondary counter-band, heavily reduced.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            tokens.meshBlobSecondary.opacity(0.28),
                            tokens.meshBlobHighlight.opacity(0.14),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width * 0.24, height: height * 1.2)
                .blur(radius: scale * 0.14)
                .rotationEffect(.degrees(-20 + Double(cos(phase * 0.9)) * 4))
                .offset(x: -width * 0.18 + driftX2 * 0.6, y: height * 0.06 + driftY2 * 0.3)
                .blendMode(.screen)
                .opacity(0.35)

            // Top rim glow — secondary, soft ceiling only.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            tokens.meshBlobHighlight.opacity(0.28),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.0),
                        startRadius: 0,
                        endRadius: scale * 0.6
                    )
                )
                .frame(width: width * 1.15, height: height * 0.5)
                .blur(radius: scale * 0.14)
                .offset(y: -height * 0.3 + driftY * 0.2)
                .blendMode(.plusLighter)
                .opacity(0.45)

            // Floor darken — keeps noir “void” under the shaft.
            LinearGradient(
                colors: [
                    Color.clear,
                    tokens.meshBase.opacity(0.35),
                    tokens.meshBase.opacity(0.75)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.35),
                endPoint: .bottom
            )
            .blendMode(.multiply)
        }
    }
}
