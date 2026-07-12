//
//  ThemeBackgroundView.swift
//  Light Stats
//
//  Mesh stack (bottom → top):
//    1. Light field (film S-curve vs noir vertical shaft) — bold enough to read
//    2. Soft radial reading veil (center only) — text contrast without burying art
//    3. Shared film grain — optional; always on top so grit stays crisp
//
//  Do NOT paint a full-frame opaque scrim over this; it kills grain + light shapes.
//

import SwiftUI

struct ThemeBackgroundView: View {
    let tokens: ThemeTokens
    let appearance: ThemeAppearanceConfiguration
    var cornerRadius: CGFloat = 12
    var configuresWindow: Bool = false
    var fallbackMaterial: NSVisualEffectView.Material = .sidebar

    init(
        tokens: ThemeTokens,
        appearance: ThemeAppearanceConfiguration? = nil,
        cornerRadius: CGFloat = 12,
        configuresWindow: Bool = false,
        fallbackMaterial: NSVisualEffectView.Material = .sidebar
    ) {
        self.tokens = tokens
        self.appearance = appearance ?? .defaults(for: tokens.theme)
        self.cornerRadius = cornerRadius
        self.configuresWindow = configuresWindow
        self.fallbackMaterial = fallbackMaterial
    }

    var body: some View {
        Group {
            if tokens.usesGlass {
                GlassBackgroundView(
                    cornerRadius: cornerRadius,
                    fallbackMaterial: fallbackMaterial,
                    configuresWindow: configuresWindow
                )
            } else if tokens.usesMesh {
                FluidMeshBackground(tokens: tokens, appearance: appearance)
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
    let appearance: ThemeAppearanceConfiguration
    @State private var phaseAnchorDate = Date()
    @State private var phaseAnchor: CGFloat = 0

    /// Same grit strength for film + noir; film only warms the tint.
    private var grainWarmth: Double { tokens.theme == .film ? 0.5 : 0 }
    private var grainOpacity: Double { appearance.grainEnabled ? 0.42 : 0 }

    private var animationPaused: Bool {
        appearance.lightFlow < 0.02
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: animationPaused)) { context in
            let phase = phase(at: context.date, flow: appearance.lightFlow)

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let scale = min(width, height)
                // Keep the light mass inside the visible composition at slider extremes.
                let shiftX = CGFloat(appearance.lightPositionX - 0.5) * width * 0.4
                let shiftY = CGFloat(appearance.lightPositionY - 0.5) * height * 0.3

                ZStack {
                    // 1) Light art — flattened for blur cost.
                    Group {
                        switch tokens.theme {
                        case .film:
                            FilmLightField(
                                tokens: tokens,
                                width: width,
                                height: height,
                                scale: scale,
                                phase: phase,
                                shiftX: shiftX,
                                shiftY: shiftY
                            )
                        case .noir:
                            NoirLightField(
                                tokens: tokens,
                                width: width,
                                height: height,
                                scale: scale,
                                phase: phase,
                                shiftX: shiftX,
                                shiftY: shiftY
                            )
                        default:
                            tokens.meshBase
                        }
                    }
                    .drawingGroup(opaque: true, colorMode: .extendedLinear)

                    // 2) Soft center darken — tracks light bias slightly so shift stays visible.
                    readingVeil(
                        width: width,
                        height: height,
                        scale: scale,
                        posX: appearance.lightPositionX,
                        posY: appearance.lightPositionY
                    )

                    // 3) Grain on top when enabled — must stay outside drawingGroup.
                    GrainTextureView(opacity: grainOpacity, warmth: grainWarmth)
                }
                .frame(width: width, height: height)
            }
        }
        .onChange(of: appearance.lightFlow) { oldFlow, _ in
            let now = Date()
            phaseAnchor = phase(at: now, flow: oldFlow)
            phaseAnchorDate = now
        }
    }

    /// Integrate from a retained anchor so changing speed never teleports the light field.
    private func phase(at date: Date, flow: Double) -> CGFloat {
        guard flow >= 0.02 else { return phaseAnchor }
        let elapsed = date.timeIntervalSince(phaseAnchorDate)
        let radiansPerSecond = CGFloat(flow) * .pi / 3
        return phaseAnchor + CGFloat(elapsed) * radiansPerSecond
    }

    /// Center opacity keeps cream text readable; rim stays clear for light shapes.
    private func readingVeil(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        posX: Double,
        posY: Double
    ) -> some View {
        let center = tokens.theme == .film
            ? Color(red: 0.06, green: 0.03, blue: 0.02)
            : Color.black
        // Veil follows position a little so light shift isn’t canceled by a fixed scrim.
        let veilX = 0.5 + (posX - 0.5) * 0.35
        let veilY = 0.48 + (posY - 0.5) * 0.3

        return RadialGradient(
            colors: [
                center.opacity(0.48),
                center.opacity(0.24),
                center.opacity(0.06),
                Color.clear
            ],
            center: UnitPoint(x: veilX, y: veilY),
            startRadius: scale * 0.06,
            endRadius: max(width, height) * 0.75
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
    /// Static composition bias in points, constrained by the mesh shell.
    var shiftX: CGFloat = 0
    var shiftY: CGFloat = 0

    var body: some View {
        let driftX = cos(phase) * width * 0.12
        let driftY = sin(phase * 0.75) * height * 0.08
        let driftX2 = cos(phase * 0.95 + 1.1) * width * 0.09
        let driftY2 = sin(phase * 1.05 + 0.5) * height * 0.075
        let phaseX = cos(phase) * 0.08
        let ribbonTwist = Double(sin(phase)) * 9
        let ribbonTwist2 = Double(cos(phase * 0.85)) * 7
        // Slight composition tilt from horizontal position.
        let compositionTilt = Double(shiftX / max(width, 1)) * 12

        return ZStack {
            tokens.meshBase

            // Keep the full-frame wash fixed so position extremes never expose an edge.
            LinearGradient(
                colors: [
                    tokens.meshBlobHighlight.opacity(0.75),
                    tokens.meshBlobSecondary.opacity(0.60),
                    tokens.meshBlobPrimary.opacity(0.70),
                    tokens.meshBase
                ],
                startPoint: UnitPoint(x: 0.0 + phaseX, y: 0.0),
                endPoint: UnitPoint(x: 1.0, y: 1.0)
            )

            // Position controls pan only the oversized light masses above the wash.
            ZStack {
                // Coral mass (lower-right lobe of the S).
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                tokens.meshBlobSecondary.opacity(0.98),
                                tokens.meshBlobSecondary.opacity(0.60),
                                tokens.meshBlobPrimary.opacity(0.30),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.65, y: 0.6),
                            startRadius: 0,
                            endRadius: scale * 0.9
                        )
                    )
                    .frame(width: width * 1.7, height: height * 1.25)
                    .blur(radius: scale * 0.18)
                    .offset(x: width * 0.22 + driftX, y: height * 0.2 + driftY)
                    .blendMode(.plusLighter)

                // Burgundy counter-lobe.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                tokens.meshBlobPrimary.opacity(0.60),
                                tokens.meshBlobPrimary.opacity(0.25),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: scale * 0.75
                        )
                    )
                    .frame(width: width * 1.2, height: height * 0.9)
                    .blur(radius: scale * 0.18)
                    .offset(x: -width * 0.22 + driftX * 0.45, y: -height * 0.1 - driftY * 0.35)
                    .blendMode(.normal)
                    .opacity(0.6)

                // Primary S-ribbon.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                tokens.meshBlobHighlight.opacity(0.90),
                                tokens.meshBlobSecondary.opacity(0.80),
                                tokens.meshBlobHighlight.opacity(0.50),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 1.85, height: height * 0.40)
                    .blur(radius: scale * 0.08)
                    .rotationEffect(.degrees(-26 + ribbonTwist + compositionTilt))
                    .offset(x: driftX * 0.8, y: height * 0.04 + driftY * 0.7)
                    .blendMode(.screen)

                // Secondary ribbon.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                tokens.meshBlobSecondary.opacity(0.35),
                                tokens.meshBlobHighlight.opacity(0.20),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 1.35, height: height * 0.18)
                    .blur(radius: scale * 0.12)
                    .rotationEffect(.degrees(-16 + ribbonTwist2 + compositionTilt * 0.5))
                    .offset(x: -width * 0.06 + driftX2, y: -height * 0.14 + driftY2)
                    .blendMode(.screen)
                    .opacity(0.5)

                // Cream bloom.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                tokens.meshBlobHighlight.opacity(0.40),
                                tokens.meshBlobHighlight.opacity(0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: scale * 0.55
                        )
                    )
                    .frame(width: width * 0.9, height: height * 0.7)
                    .blur(radius: scale * 0.14)
                    .offset(x: -width * 0.32 + driftX2 * 0.4, y: -height * 0.32 + driftY2 * 0.3)
                    .blendMode(.plusLighter)
                    .opacity(0.55)
            }
            // Pan the light masses without moving the full-frame coverage layer.
            .offset(x: shiftX, y: shiftY)
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
    let shiftX: CGFloat
    let shiftY: CGFloat

    var body: some View {
        let driftX = sin(phase * 0.9) * width * 0.04
        let driftY = cos(phase) * height * 0.065
        let driftX2 = cos(phase * 1.1 + 0.5) * width * 0.05
        let driftY2 = sin(phase * 0.7 + 1.0) * height * 0.05

        return ZStack {
            tokens.meshBase

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
                .offset(x: width * 0.14 + driftX + shiftX, y: -height * 0.1 + driftY + shiftY)
                .blendMode(.screen)

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
                .offset(x: -width * 0.26 + driftX2 + shiftX, y: height * 0.24 + driftY2 + shiftY)
                .blendMode(.plusLighter)
                .opacity(0.4)

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
                .offset(x: width * 0.1 + driftX * 0.5 + shiftX, y: driftY * 0.35 + shiftY)
                .blendMode(.screen)

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
                .offset(x: -width * 0.18 + driftX2 * 0.6 + shiftX, y: height * 0.06 + driftY2 * 0.3 + shiftY)
                .blendMode(.screen)
                .opacity(0.35)

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
                .offset(x: shiftX, y: -height * 0.3 + driftY * 0.2 + shiftY)
                .blendMode(.plusLighter)
                .opacity(0.45)

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
