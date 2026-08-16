//
//  ThemeBackgroundView.swift
//  Light Stats
//
//  Mesh stack (bottom → top):
//    1. Light field (FilmMeshRenderer vs NoirMeshRenderer)
//    2. Soft radial reading veil (center only)
//    3. Shared film grain — optional; always on top so grit stays crisp
//
//  Do NOT paint a full-frame opaque scrim over this; it kills grain + light shapes.
//  This view receives only `BackgroundConfiguration` — it does not know `AppTheme`.
//

import SwiftUI

struct ThemeBackgroundView: View {
    let configuration: BackgroundConfiguration
    let appearance: ThemeAppearanceConfiguration
    var cornerRadius: CGFloat = 12
    var configuresWindow: Bool = false
    var fallbackMaterial: NSVisualEffectView.Material = .sidebar

    init(
        configuration: BackgroundConfiguration,
        appearance: ThemeAppearanceConfiguration? = nil,
        cornerRadius: CGFloat = 12,
        configuresWindow: Bool = false,
        fallbackMaterial: NSVisualEffectView.Material = .sidebar
    ) {
        self.configuration = configuration
        self.appearance = appearance ?? .defaults
        self.cornerRadius = cornerRadius
        self.configuresWindow = configuresWindow
        self.fallbackMaterial = fallbackMaterial
    }

    var body: some View {
        Group {
            switch configuration.kind {
            case .glass:
                GlassBackgroundView(
                    cornerRadius: cornerRadius,
                    fallbackMaterial: fallbackMaterial,
                    configuresWindow: configuresWindow
                )
            case .mesh:
                ZStack {
                    configuration.canvas
                    FluidMeshBackground(configuration: configuration, appearance: appearance)
                        .id(configuration.meshRenderer)
                }
            case .solid:
                configuration.canvas
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Mesh shell

private struct FluidMeshBackground: View {
    let configuration: BackgroundConfiguration
    let appearance: ThemeAppearanceConfiguration
    @State private var phaseAnchorDate = Date()
    @State private var phaseAnchor: CGFloat = 0

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
                    Group {
                        switch configuration.meshRenderer {
                        case .film:
                            FilmMeshRenderer(
                                configuration: configuration,
                                width: width,
                                height: height,
                                scale: scale,
                                phase: phase,
                                shiftX: motion.x,
                                shiftY: motion.y
                            )
                        case .noir:
                            NoirMeshRenderer(
                                configuration: configuration,
                                width: width,
                                height: height,
                                scale: scale,
                                phase: phase,
                                shiftX: motion.x,
                                shiftY: motion.y
                            )
                        case nil:
                            configuration.meshBase
                        }
                    }
                    .drawingGroup(opaque: true, colorMode: .extendedLinear)
                    .id(configuration.meshRenderer)

                    readingVeil(
                        width: width,
                        height: height,
                        scale: scale,
                        posX: 0.5 + Double(motion.x / max(width, 1)),
                        posY: 0.5 + Double(motion.y / max(height, 1))
                    )

                    GrainTextureView(opacity: grainOpacity, warmth: configuration.grainWarmth)
                }
                .frame(width: width, height: height)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: appearance.dynamics) { oldDynamics, _ in
            let now = Date()
            phaseAnchor = phase(at: now, dynamics: oldDynamics)
            phaseAnchorDate = now
        }
    }

    private func phase(at date: Date, dynamics: Double) -> CGFloat {
        guard dynamics >= 0.02 else { return phaseAnchor }
        let elapsed = date.timeIntervalSince(phaseAnchorDate)
        let smoothDynamics = dynamics * dynamics * (3 - 2 * dynamics)
        let travel = CGFloat(elapsed * smoothDynamics) * .pi / 3
        let slowBand = sin((phaseAnchor + travel) * 0.19) - sin(phaseAnchor * 0.19)
        let detailBand = sin((phaseAnchor + travel) * 0.37 + 1.2) - sin(phaseAnchor * 0.37 + 1.2)
        return phaseAnchor + travel + slowBand * 0.12 + detailBand * 0.06
    }

    private func motionOffset(
        phase: CGFloat,
        dynamics: Double,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        guard dynamics >= 0.02 else { return .zero }
        let smoothDynamics = CGFloat(dynamics * dynamics * (3 - 2 * dynamics))
        let motion = configuration.motion
        let amplitude = motion.amplitudeBase + smoothDynamics * motion.amplitudeSpan
        let positionX = sin(phase * 0.61 + motion.phaseOffset) * motion.horizontalPrimary
            + sin(phase * 1.17 + 1.1) * motion.horizontalSecondary
        let positionY = cos(phase * 0.43 + motion.phaseOffset) * motion.verticalPrimary
            + sin(phase * 0.83 + 2.0) * motion.verticalSecondary
        return CGPoint(x: width * amplitude * positionX, y: height * amplitude * positionY)
    }

    private func readingVeil(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        posX: Double,
        posY: Double
    ) -> some View {
        let center = configuration.veilCenter
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
