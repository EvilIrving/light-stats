//
//  InkNightBackgroundTheme.swift
//  Light Stats
//

import CoreGraphics
import Foundation

/// Complete, isolated background definition for the Ink Night theme.
enum InkNightBackgroundTheme {
    static let definition: BackgroundThemeDefinition = {
        let palette = Palette()
        return BackgroundThemeDefinition(
            identifier: "ink-night-background",
            sceneModel: SceneModel(palette: palette),
            occlusionModel: CloudOcclusionModel(palette: palette),
            readabilityPolicy: ReadabilityPolicy(palette: palette),
            materialEffects: [
                AnyBackgroundMaterialEffect(
                    GrainBackgroundMaterial(
                        identifier: "ink-night-grain",
                        opacity: 0.22,
                        warmth: 0
                    )
                ),
                AnyBackgroundMaterialEffect(
                    FilmVignetteBackgroundMaterial(
                        identifier: "ink-night-film-vignette",
                        tint: palette.vignette,
                        opacity: 0.18
                    )
                )
            ]
        )
    }()

    private struct Palette: Sendable {
        let base = BackgroundSceneFrame.Color(red: 0.025, green: 0.028, blue: 0.052)
        let moonlight = BackgroundSceneFrame.Color(red: 0.57, green: 0.64, blue: 0.86)
        let cloud = BackgroundSceneFrame.Color(red: 0.026, green: 0.031, blue: 0.061)
        let readingInk = BackgroundSceneFrame.Color(red: 0.015, green: 0.018, blue: 0.035)
        let vignette = BackgroundSceneFrame.Color(red: 0.07, green: 0.08, blue: 0.16)
    }

    private struct SceneModel: BackgroundSceneModel {
        let palette: Palette

        func makeFrame(
            time: TimeInterval,
            size: CGSize,
            configuration: BackgroundSceneConfiguration
        ) -> BackgroundSceneFrame {
            let smoothIntensity = smoothstep(configuration.intensity)
            let motionAmplitude = CGFloat(0.42 + smoothIntensity * 0.58)
            let lunarPhase = CGFloat(time * 2 * Double.pi / 58)
            let source = CGPoint(
                x: size.width * (0.5 + sin(lunarPhase) * 0.72 * motionAmplitude),
                y: size.height * (-0.28 + cos(lunarPhase * 0.73 + 0.4) * 0.055 * motionAmplitude)
            )
            let target = CGPoint(
                x: size.width * (0.5 + sin(lunarPhase * 0.47 + 1.2) * 0.09 * motionAmplitude),
                y: size.height * 1.12
            )
            let moonlight = BackgroundSceneFrame.ProjectedLight(
                source: source,
                target: target,
                sourceWidth: max(size.width * 0.12, 56),
                targetWidth: max(size.width * 0.98, size.height * 0.50),
                color: palette.moonlight,
                intensity: 0.66,
                softness: min(size.width, size.height) * 0.085,
                blendMode: .screen
            )
            return BackgroundSceneFrame(primitives: [
                .colorFill(palette.base),
                .projectedLight(moonlight)
            ])
        }

        private func smoothstep(_ value: Double) -> Double {
            value * value * (3 - 2 * value)
        }
    }

    private struct CloudOcclusionModel: BackgroundOcclusionModel {
        let palette: Palette

        func makeOcclusions(
            time: TimeInterval,
            size: CGSize,
            configuration: BackgroundSceneConfiguration
        ) -> [BackgroundSceneFrame.Primitive] {
            let smoothIntensity = configuration.intensity * configuration.intensity
                * (3 - 2 * configuration.intensity)
            let motionAmplitude = CGFloat(0.35 + smoothIntensity * 0.65)
            let speedScale = 0.55 + smoothIntensity * 0.75
            let coverageWave = 0.5 + sin(time * 2 * Double.pi / 31) * 0.27
                + sin(time * 2 * Double.pi / 19 + 1.4) * 0.15
                + sin(time * 2 * Double.pi / 43 + 3.6) * 0.08
            var primitives: [BackgroundSceneFrame.Primitive] = []
            primitives.reserveCapacity(Self.clouds.count)

            for cloud in Self.clouds {
                let progress = wrappedProgress(time * cloud.speed * speedScale + cloud.phase)
                let localWave = sin(time * cloud.edgeFrequency + cloud.phase * 2 * Double.pi)
                let opticalDepth = max(
                    cloud.density + coverageWave * 1.18 + localWave * 0.16,
                    0.42
                )
                let extinction = min(1 - exp(-opticalDepth * 1.55), 0.985)
                let center = CGPoint(
                    x: size.width * (-0.68 + CGFloat(progress) * 2.36),
                    y: size.height * (
                        cloud.positionY + CGFloat(localWave) * cloud.verticalDrift * motionAmplitude
                    )
                )
                let mask = BackgroundSceneFrame.SoftMask(
                    center: center,
                    size: CGSize(
                        width: size.width * (cloud.width + CGFloat(extinction) * 0.22),
                        height: size.height * (cloud.height + CGFloat(extinction) * 0.07)
                    ),
                    angle: cloud.angle + CGFloat(localWave) * 0.025 * motionAmplitude,
                    shape: .ellipse,
                    color: palette.cloud,
                    opacity: extinction,
                    softness: min(size.width, size.height)
                        * (0.035 + CGFloat(0.5 + localWave * 0.5) * 0.055),
                    blendMode: .normal,
                    role: .lightOccluder,
                    bodyOpacity: 0.05 + extinction * 0.11
                )
                primitives.append(.softMask(mask))
            }
            return primitives
        }

        private func wrappedProgress(_ value: Double) -> Double {
            value - floor(value)
        }

        private struct CloudBand: Sendable {
            let positionY: CGFloat
            let width: CGFloat
            let height: CGFloat
            let angle: CGFloat
            let phase: Double
            let speed: Double
            let edgeFrequency: Double
            let verticalDrift: CGFloat
            let density: Double
        }

        private static let clouds: [CloudBand] = [
            CloudBand(
                positionY: 0.20, width: 0.92, height: 0.16, angle: -0.11,
                phase: 0.08, speed: 0.011, edgeFrequency: 0.31, verticalDrift: 0.030, density: 0.58
            ),
            CloudBand(
                positionY: 0.39, width: 1.02, height: 0.20, angle: -0.07,
                phase: 0.36, speed: 0.015, edgeFrequency: 0.24, verticalDrift: 0.040, density: 0.72
            ),
            CloudBand(
                positionY: 0.61, width: 0.96, height: 0.18, angle: -0.14,
                phase: 0.61, speed: 0.018, edgeFrequency: 0.28, verticalDrift: 0.032, density: 0.64
            ),
            CloudBand(
                positionY: 0.79, width: 0.86, height: 0.15, angle: -0.09,
                phase: 0.84, speed: 0.013, edgeFrequency: 0.35, verticalDrift: 0.025, density: 0.52
            )
        ]
    }

    private struct ReadabilityPolicy: BackgroundReadabilityPolicy {
        let palette: Palette

        func makeRegions(
            size: CGSize,
            configuration _: BackgroundSceneConfiguration
        ) -> [BackgroundSceneFrame.Primitive] {
            let insetX = size.width * 0.07
            let insetY = size.height * 0.04
            let region = BackgroundSceneFrame.ReadabilityRegion(
                bounds: CGRect(
                    x: insetX,
                    y: insetY,
                    width: size.width - insetX * 2,
                    height: size.height - insetY * 2
                ),
                cornerRadius: min(size.width, size.height) * 0.10,
                color: palette.readingInk,
                opacity: 0.12,
                softness: min(size.width, size.height) * 0.065
            )
            return [.readabilityRegion(region)]
        }
    }
}
