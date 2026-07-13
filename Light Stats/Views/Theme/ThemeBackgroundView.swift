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
                // NSVisualEffectView / NSGlassEffectView fills bounds and accepts hits,
                // so wheel events stay inside the non-opaque panel.
                GlassBackgroundView(
                    cornerRadius: cornerRadius,
                    fallbackMaterial: fallbackMaterial,
                    configuresWindow: configuresWindow
                )
            } else if tokens.usesMesh {
                // Mesh art disables hit testing (oversized light fields would otherwise
                // leak targets past visual clip). FluidMeshBackground flattens its
                // canvas and art into one opaque surface for the non-opaque panel.
                FluidMeshBackground(tokens: tokens, appearance: appearance)
                    .id(tokens.theme)
            } else {
                tokens.canvas
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Match visual clip for hit testing — clipShape alone does not always
        // constrain hits when children are offset larger than the frame.
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
        appearance.dynamics < 0.02
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: animationPaused)) { context in
            let phase = phase(at: context.date, dynamics: appearance.dynamics)

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let scale = min(width, height)
                let motion = motionOffset(
                    phase: phase,
                    dynamics: appearance.dynamics,
                    width: width,
                    height: height
                )

                ZStack {
                    tokens.canvas

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
                                shiftX: motion.x,
                                shiftY: motion.y
                            )
                        case .noir:
                            NoirLightField(
                                tokens: tokens,
                                width: width,
                                height: height,
                                scale: scale,
                                phase: phase,
                                shiftX: motion.x,
                                shiftY: motion.y
                            )
                        default:
                            tokens.meshBase
                        }
                    }
                    .id(tokens.theme)

                    // 2) Soft center darken — tracks light bias slightly so shift stays visible.
                    readingVeil(
                        width: width,
                        height: height,
                        scale: scale,
                        posX: 0.5 + Double(motion.x / max(width, 1)),
                        posY: 0.5 + Double(motion.y / max(height, 1))
                    )

                    // 3) Grain on top when enabled — must stay outside drawingGroup.
                    GrainTextureView(opacity: grainOpacity, warmth: grainWarmth)
                }
                .frame(width: width, height: height)
                // One opaque pass keeps the panel's full alpha without the CPU and
                // memory cost of nesting a second full-frame drawing group.
                .drawingGroup(opaque: true, colorMode: .extendedLinear)
            }
        }
        // Light ellipses/capsules are larger than the view and drift with negative Y.
        // Keep them out of the hit-test tree so they never intercept sibling controls
        // (settings theme tiles sit directly above the live preview).
        .allowsHitTesting(false)
        .onChange(of: appearance.dynamics) { oldDynamics, _ in
            let now = Date()
            phaseAnchor = phase(at: now, dynamics: oldDynamics)
            phaseAnchorDate = now
        }
    }

    /// Continuous phase with two low-frequency bands for organic acceleration and deceleration.
    private func phase(at date: Date, dynamics: Double) -> CGFloat {
        guard dynamics >= 0.02 else { return phaseAnchor }
        let elapsed = date.timeIntervalSince(phaseAnchorDate)
        let smoothDynamics = dynamics * dynamics * (3 - 2 * dynamics)
        let travel = CGFloat(elapsed * smoothDynamics) * .pi / 3
        let slowBand = sin((phaseAnchor + travel) * 0.19) - sin(phaseAnchor * 0.19)
        let detailBand = sin((phaseAnchor + travel) * 0.37 + 1.2) - sin(phaseAnchor * 0.37 + 1.2)
        return phaseAnchor + travel + slowBand * 0.12 + detailBand * 0.06
    }

    /// Theme-specific quasi-periodic Lissajous orbit driven by the single dynamics value.
    private func motionOffset(
        phase: CGFloat,
        dynamics: Double,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        guard dynamics >= 0.02 else { return .zero }
        let smoothDynamics = CGFloat(dynamics * dynamics * (3 - 2 * dynamics))
        let isNoir = tokens.theme == .noir
        // Noir starts restrained but opens into a much wider orbit at the lively end.
        let amplitude = isNoir ? 0.35 + smoothDynamics * 1.15 : 0.68 + smoothDynamics * 0.32
        let phaseOffset: CGFloat = isNoir ? 1.35 : 0.45
        let horizontalPrimary: CGFloat = isNoir ? 0.14 : 0.105
        let horizontalSecondary: CGFloat = isNoir ? 0.05 : 0.038
        let verticalPrimary: CGFloat = isNoir ? 0.12 : 0.065
        let verticalSecondary: CGFloat = isNoir ? 0.045 : 0.028
        let positionX = sin(phase * 0.61 + phaseOffset) * horizontalPrimary
            + sin(phase * 1.17 + 1.1) * horizontalSecondary
        let positionY = cos(phase * 0.43 + phaseOffset) * verticalPrimary
            + sin(phase * 0.83 + 2.0) * verticalSecondary
        return CGPoint(x: width * amplitude * positionX, y: height * amplitude * positionY)
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
