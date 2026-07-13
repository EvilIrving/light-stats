//
//  ThemeBackgroundView.swift
//  Light Stats
//
//  Mesh stack (bottom → top):
//    1. Light field (moving radial sources + sinusoidal flow bands)
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
                        case .film, .noir:
                            FlowLightField(
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

// MARK: - Flow light field

private struct FlowLightField: View {
    private struct FieldPoint {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let strength: Double
        let color: Color
    }

    let tokens: ThemeTokens
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let phase: CGFloat
    let shiftX: CGFloat
    let shiftY: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(tokens.meshBase))
            drawWash(in: &context, size: size)
            drawBlobs(in: &context, size: size)
            drawFlowBands(in: &context, size: size)
            drawEdgeShade(in: &context, size: size)
        }
        .background(tokens.meshBase)
    }

    private var isNoir: Bool {
        tokens.theme == .noir
    }

    private var fieldPoints: [FieldPoint] {
        let baseShiftX = shiftX / max(width, 1)
        let baseShiftY = shiftY / max(height, 1)
        if isNoir {
            return [
                FieldPoint(
                    x: 0.57 + baseShiftX + sin(phase * 0.55 + 0.4) * 0.05,
                    y: 0.24 + baseShiftY + cos(phase * 0.47) * 0.06,
                    radius: 0.78,
                    strength: 0.86,
                    color: tokens.meshBlobHighlight
                ),
                FieldPoint(
                    x: 0.32 + baseShiftX + cos(phase * 0.63 + 1.1) * 0.07,
                    y: 0.62 + baseShiftY + sin(phase * 0.51 + 0.8) * 0.06,
                    radius: 0.66,
                    strength: 0.44,
                    color: tokens.meshBlobSecondary
                ),
                FieldPoint(
                    x: 0.62 + baseShiftX + sin(phase * 0.39 + 2.2) * 0.04,
                    y: -0.06 + baseShiftY + cos(phase * 0.58 + 0.5) * 0.04,
                    radius: 0.48,
                    strength: 0.34,
                    color: tokens.meshBlobHighlight
                )
            ]
        }
        return [
            FieldPoint(
                x: 0.68 + baseShiftX + cos(phase * 0.52) * 0.09,
                y: 0.62 + baseShiftY + sin(phase * 0.43 + 0.6) * 0.08,
                radius: 0.74,
                strength: 0.92,
                color: tokens.meshBlobSecondary
            ),
            FieldPoint(
                x: 0.28 + baseShiftX + sin(phase * 0.48 + 1.4) * 0.08,
                y: 0.20 + baseShiftY + cos(phase * 0.38 + 0.2) * 0.06,
                radius: 0.62,
                strength: 0.54,
                color: tokens.meshBlobHighlight
            ),
            FieldPoint(
                x: 0.20 + baseShiftX + cos(phase * 0.57 + 2.0) * 0.05,
                y: 0.76 + baseShiftY + sin(phase * 0.49 + 1.1) * 0.05,
                radius: 0.56,
                strength: 0.42,
                color: tokens.meshBlobPrimary
            )
        ]
    }

    private func drawWash(in context: inout GraphicsContext, size: CGSize) {
        let startX = isNoir ? 0.5 + sin(phase) * 0.04 : 0.06 + cos(phase) * 0.06
        let endX = isNoir ? 0.5 : 0.96
        let endY = isNoir ? 1.0 : 0.94
        let colors = isNoir
            ? [
                tokens.meshBlobHighlight.opacity(0.34),
                tokens.meshBlobSecondary.opacity(0.28),
                tokens.meshBlobPrimary.opacity(0.42),
                tokens.meshBase
            ]
            : [
                tokens.meshBlobHighlight.opacity(0.58),
                tokens.meshBlobSecondary.opacity(0.50),
                tokens.meshBlobPrimary.opacity(0.56),
                tokens.meshBase
            ]
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: colors),
                startPoint: CGPoint(x: size.width * startX, y: 0),
                endPoint: CGPoint(x: size.width * endX, y: size.height * endY)
            )
        )
    }

    private func drawBlobs(in context: inout GraphicsContext, size: CGSize) {
        for point in fieldPoints {
            let center = CGPoint(x: size.width * point.x, y: size.height * point.y)
            let radius = scale * point.radius
            let bounds = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.drawLayer { layer in
                layer.blendMode = isNoir ? .screen : .plusLighter
                layer.addFilter(.blur(radius: scale * (isNoir ? 0.11 : 0.13)))
                layer.fill(
                    Path(bounds),
                    with: .radialGradient(
                        Gradient(colors: [
                            point.color.opacity(point.strength),
                            point.color.opacity(point.strength * 0.45),
                            tokens.meshBase.opacity(point.strength * 0.10),
                            Color.clear
                        ]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
    }

    private func drawFlowBands(in context: inout GraphicsContext, size: CGSize) {
        let bandCount = isNoir ? 3 : 4
        let angle = isNoir ? CGFloat.pi * 0.55 : -CGFloat.pi * 0.15
        let normal = CGVector(dx: -sin(angle), dy: cos(angle))
        let tangent = CGVector(dx: cos(angle), dy: sin(angle))
        let origin = CGPoint(
            x: size.width * (isNoir ? 0.55 : 0.48) + shiftX * 0.35,
            y: size.height * (isNoir ? 0.42 : 0.48) + shiftY * 0.35
        )

        for index in 0..<bandCount {
            let wave = sin(phase * (0.46 + CGFloat(index) * 0.08) + CGFloat(index) * 1.7)
            let distance = (CGFloat(index) - CGFloat(bandCount - 1) / 2) * scale * (isNoir ? 0.18 : 0.14)
            let curveOffset = wave * scale * (isNoir ? 0.09 : 0.12)
            let center = CGPoint(
                x: origin.x + normal.dx * (distance + curveOffset),
                y: origin.y + normal.dy * (distance + curveOffset)
            )
            let length = scale * (isNoir ? 2.2 : 2.5)
            let thickness = scale * (isNoir ? 0.23 : 0.18) * (1 - CGFloat(index) * 0.12)
            let rect = CGRect(
                x: center.x - length / 2,
                y: center.y - thickness / 2,
                width: length,
                height: thickness
            )
            var band = Path(roundedRect: rect, cornerRadius: thickness / 2)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle + wave * 0.08)
                .translatedBy(x: -center.x, y: -center.y)
            band = band.applying(transform)
            context.drawLayer { layer in
                layer.blendMode = .screen
                layer.addFilter(.blur(radius: scale * (isNoir ? 0.07 : 0.06)))
                layer.fill(
                    band,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.clear,
                            tokens.meshBlobHighlight.opacity(isNoir ? 0.48 : 0.58),
                            tokens.meshBlobSecondary.opacity(isNoir ? 0.30 : 0.50),
                            Color.clear
                        ]),
                        startPoint: CGPoint(
                            x: center.x - tangent.dx * length / 2,
                            y: center.y - tangent.dy * length / 2
                        ),
                        endPoint: CGPoint(
                            x: center.x + tangent.dx * length / 2,
                            y: center.y + tangent.dy * length / 2
                        )
                    )
                )
            }
        }
    }

    private func drawEdgeShade(in context: inout GraphicsContext, size: CGSize) {
        guard isNoir else { return }
        context.drawLayer { layer in
            layer.blendMode = .multiply
            layer.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [
                        Color.clear,
                        tokens.meshBase.opacity(0.35),
                        tokens.meshBase.opacity(0.78)
                    ]),
                    startPoint: CGPoint(x: size.width * 0.5, y: size.height * 0.32),
                    endPoint: CGPoint(x: size.width * 0.5, y: size.height)
                )
            )
        }
    }
}
