//
//  SunGoldBackgroundTheme.swift
//  Light Stats
//

import CoreGraphics
import Foundation

/// Complete, isolated background definition for the Sun Gold theme.
enum SunGoldBackgroundTheme {
    static let definition: BackgroundThemeDefinition = {
        let palette = Palette()
        return BackgroundThemeDefinition(
            identifier: "sun-gold-background",
            sceneModel: SceneModel(palette: palette),
            occlusionModel: TreeShadowModel(palette: palette),
            readabilityPolicy: ReadabilityPolicy(palette: palette),
            materialEffects: [
                AnyBackgroundMaterialEffect(
                    GrainBackgroundMaterial(
                        identifier: "sun-gold-grain",
                        opacity: 0.25,
                        warmth: 0.62
                    )
                ),
                AnyBackgroundMaterialEffect(
                    FilmVignetteBackgroundMaterial(
                        identifier: "sun-gold-film-vignette",
                        tint: palette.vignette,
                        opacity: 0.16
                    )
                )
            ]
        )
    }()

    private struct Palette: Sendable {
        let base = BackgroundSceneFrame.Color(red: 0.15, green: 0.065, blue: 0.045)
        let sunCore = BackgroundSceneFrame.Color(red: 1.0, green: 0.52, blue: 0.28)
        let sunEdge = BackgroundSceneFrame.Color(red: 0.78, green: 0.14, blue: 0.09)
        let treeShadow = BackgroundSceneFrame.Color(red: 0.045, green: 0.024, blue: 0.018)
        let readingInk = BackgroundSceneFrame.Color(red: 0.07, green: 0.03, blue: 0.025)
        let vignette = BackgroundSceneFrame.Color(red: 0.32, green: 0.11, blue: 0.06)
    }

    private struct SceneModel: BackgroundSceneModel {
        let palette: Palette

        func makeFrame(
            time: TimeInterval,
            size: CGSize,
            configuration: BackgroundSceneConfiguration
        ) -> BackgroundSceneFrame {
            let smoothIntensity = smoothstep(configuration.intensity)
            let travelAmplitude = 0.45 + smoothIntensity * 0.55
            let phase = CGFloat(time * 2 * Double.pi / 62)
            let breathPhase = time * 2 * Double.pi / 23
            let center = CGPoint(
                x: size.width * (0.5 + sin(phase) * 0.92 * travelAmplitude),
                y: size.height * (0.23 + cos(phase * 0.41 + 0.7) * 0.055 * travelAmplitude)
            )
            let brightness = 0.79 + sin(breathPhase) * 0.055 * Double(0.35 + smoothIntensity * 0.65)
            let sun = BackgroundSceneFrame.RadialLight(
                center: center,
                radius: max(size.width, size.height) * 0.88,
                innerColor: palette.sunCore,
                outerColor: palette.sunEdge,
                intensity: brightness,
                softness: min(size.width, size.height) * 0.045,
                blendMode: .plusLighter
            )
            return BackgroundSceneFrame(primitives: [
                .colorFill(palette.base),
                .radialLight(sun)
            ])
        }

        private func smoothstep(_ value: Double) -> CGFloat {
            let result = value * value * (3 - 2 * value)
            return CGFloat(result)
        }
    }

    private struct TreeShadowModel: BackgroundOcclusionModel {
        let palette: Palette

        func makeOcclusions(
            time: TimeInterval,
            size: CGSize,
            configuration: BackgroundSceneConfiguration
        ) -> [BackgroundSceneFrame.Primitive] {
            let smoothIntensity = configuration.intensity * configuration.intensity
                * (3 - 2 * configuration.intensity)
            let motionAmplitude = CGFloat(0.18 + smoothIntensity * 0.82)
            return branchShadows(time: time, size: size, amplitude: motionAmplitude)
                + leafShadows(time: time, size: size, amplitude: motionAmplitude)
        }

        private func branchShadows(
            time: TimeInterval,
            size: CGSize,
            amplitude: CGFloat
        ) -> [BackgroundSceneFrame.Primitive] {
            let diagonal = hypot(size.width, size.height)
            return Self.branches.map { branch in
                let wind = sin(CGFloat(time) * branch.frequency + branch.phase)
                let sway = wind * 0.045 * amplitude
                let mask = BackgroundSceneFrame.SoftMask(
                    center: CGPoint(
                        x: size.width * (branch.position + sway),
                        y: size.height * (0.51 + sway * 0.30)
                    ),
                    size: CGSize(width: max(22, size.width * branch.width), height: diagonal * 1.45),
                    angle: branch.angle + wind * 0.08 * amplitude,
                    shape: .capsule,
                    color: palette.treeShadow,
                    opacity: branch.opacity,
                    softness: min(size.width, size.height) * branch.softness,
                    blendMode: .multiply
                )
                return .softMask(mask)
            }
        }

        private func leafShadows(
            time: TimeInterval,
            size: CGSize,
            amplitude: CGFloat
        ) -> [BackgroundSceneFrame.Primitive] {
            Self.leaves.map { leaf in
                let flutter = sin(CGFloat(time) * leaf.frequency + leaf.phase)
                let gust = sin(CGFloat(time) * 0.23 + leaf.phase * 0.41)
                let center = CGPoint(
                    x: size.width * (leaf.positionX + (flutter * 0.040 + gust * 0.014) * amplitude),
                    y: size.height * (leaf.positionY + cos(flutter + leaf.phase) * 0.009 * amplitude)
                )
                let mask = BackgroundSceneFrame.SoftMask(
                    center: center,
                    size: CGSize(width: size.width * leaf.width, height: size.height * leaf.height),
                    angle: leaf.angle + flutter * 0.16 * amplitude,
                    shape: .ellipse,
                    color: palette.treeShadow,
                    opacity: leaf.opacity,
                    softness: min(size.width, size.height) * leaf.softness,
                    blendMode: .multiply
                )
                return .softMask(mask)
            }
        }

        private struct BranchShadow: Sendable {
            let position: CGFloat
            let width: CGFloat
            let angle: CGFloat
            let phase: CGFloat
            let frequency: CGFloat
            let opacity: Double
            let softness: CGFloat
        }

        private struct LeafShadow: Sendable {
            let positionX: CGFloat
            let positionY: CGFloat
            let width: CGFloat
            let height: CGFloat
            let angle: CGFloat
            let phase: CGFloat
            let frequency: CGFloat
            let opacity: Double
            let softness: CGFloat
        }

        private static let branches: [BranchShadow] = [
            BranchShadow(
                position: 0.08, width: 0.13, angle: -0.32,
                phase: 0.2, frequency: 0.31, opacity: 0.24, softness: 0.060
            ),
            BranchShadow(
                position: 0.50, width: 0.09, angle: -0.24,
                phase: 2.1, frequency: 0.38, opacity: 0.19, softness: 0.052
            ),
            BranchShadow(
                position: 0.92, width: 0.16, angle: -0.37,
                phase: 4.3, frequency: 0.27, opacity: 0.26, softness: 0.068
            )
        ]

        private static let leaves: [LeafShadow] = [
            LeafShadow(
                positionX: 0.08, positionY: 0.16, width: 0.28, height: 0.12, angle: -0.28,
                phase: 0.3, frequency: 0.72, opacity: 0.20, softness: 0.052
            ),
            LeafShadow(
                positionX: 0.31, positionY: 0.30, width: 0.20, height: 0.10, angle: 0.18,
                phase: 1.2, frequency: 0.88, opacity: 0.16, softness: 0.045
            ),
            LeafShadow(
                positionX: 0.72, positionY: 0.20, width: 0.26, height: 0.13, angle: -0.12,
                phase: 2.0, frequency: 0.64, opacity: 0.19, softness: 0.056
            ),
            LeafShadow(
                positionX: 0.94, positionY: 0.38, width: 0.22, height: 0.09, angle: 0.24,
                phase: 2.8, frequency: 0.91, opacity: 0.15, softness: 0.042
            ),
            LeafShadow(
                positionX: 0.18, positionY: 0.58, width: 0.24, height: 0.12, angle: -0.20,
                phase: 3.6, frequency: 0.78, opacity: 0.18, softness: 0.050
            ),
            LeafShadow(
                positionX: 0.58, positionY: 0.66, width: 0.30, height: 0.14, angle: 0.10,
                phase: 4.4, frequency: 0.68, opacity: 0.21, softness: 0.058
            ),
            LeafShadow(
                positionX: 0.86, positionY: 0.82, width: 0.25, height: 0.11, angle: -0.16,
                phase: 5.2, frequency: 0.84, opacity: 0.17, softness: 0.048
            )
        ]
    }

    private struct ReadabilityPolicy: BackgroundReadabilityPolicy {
        let palette: Palette

        func makeRegions(
            size: CGSize,
            configuration _: BackgroundSceneConfiguration
        ) -> [BackgroundSceneFrame.Primitive] {
            let insetX = size.width * 0.075
            let insetY = size.height * 0.045
            let region = BackgroundSceneFrame.ReadabilityRegion(
                bounds: CGRect(
                    x: insetX,
                    y: insetY,
                    width: size.width - insetX * 2,
                    height: size.height - insetY * 2
                ),
                cornerRadius: min(size.width, size.height) * 0.10,
                color: palette.readingInk,
                opacity: 0.15,
                softness: min(size.width, size.height) * 0.07
            )
            return [.readabilityRegion(region)]
        }
    }
}
