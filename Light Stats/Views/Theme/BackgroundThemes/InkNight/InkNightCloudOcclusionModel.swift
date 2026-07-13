//
//  InkNightCloudOcclusionModel.swift
//  Light Stats
//

import CoreGraphics
import Foundation

struct InkNightCloudOcclusionModel: BackgroundOcclusionModel {
    let palette: InkNightBackgroundTheme.Palette

    func makeOcclusions(
        time: TimeInterval,
        size: CGSize,
        configuration: BackgroundSceneConfiguration
    ) -> [BackgroundSceneFrame.Primitive] {
        let seed = CoherentNoise.derivedSeed(configuration.sceneSeed, channel: 0x43_4C_4F_55_44)
        let coverageNoise = CoherentNoise.fractal(
            at: time * 0.047,
            seed: seed,
            octaves: 4,
            persistence: 0.55
        )
        let coverage = 0.50 + coverageNoise * 0.42
        var primitives: [BackgroundSceneFrame.Primitive] = []
        primitives.reserveCapacity(Self.clouds.count * Self.lobes.count)

        for (index, cloud) in Self.clouds.enumerated() {
            let cloudSeed = CoherentNoise.derivedSeed(seed, channel: UInt64(index) + 1)
            let speedVariation = CoherentNoise.fractal(
                at: time * 0.034 + cloud.phase,
                seed: cloudSeed,
                octaves: 3,
                persistence: 0.48
            )
            let sessionOffset = CoherentNoise.value(at: Double(index) * 3.71, seed: cloudSeed) * 0.36
            let progress = wrappedProgress(
                time * cloud.speed + cloud.phase + sessionOffset + speedVariation * 0.11
            )
            let localWave = CoherentNoise.fractal(
                at: time * cloud.edgeFrequency + cloud.phase,
                seed: CoherentNoise.derivedSeed(cloudSeed, channel: 0x45_44_47_45),
                octaves: 3,
                persistence: 0.54
            )
            let columnOpticalDepth = max(
                cloud.density + coverage * 0.72 + localWave * 0.10,
                0.18
            )
            let bandWidth = size.width * cloud.width
            let bandHeight = size.height * cloud.height
            let bandCenter = CGPoint(
                x: size.width * (-0.68 + CGFloat(progress) * 2.36),
                y: size.height * (cloud.positionY + CGFloat(localWave) * cloud.verticalDrift)
            )
            appendLobes(
                for: cloud,
                time: time,
                size: size,
                bandCenter: bandCenter,
                bandWidth: bandWidth,
                bandHeight: bandHeight,
                columnOpticalDepth: columnOpticalDepth,
                localWave: localWave,
                seed: cloudSeed,
                to: &primitives
            )
        }
        return primitives
    }

    private func appendLobes(
        for cloud: CloudBand,
        time: TimeInterval,
        size: CGSize,
        bandCenter: CGPoint,
        bandWidth: CGFloat,
        bandHeight: CGFloat,
        columnOpticalDepth: Double,
        localWave: Double,
        seed: UInt64,
        to primitives: inout [BackgroundSceneFrame.Primitive]
    ) {
        for (index, lobe) in Self.lobes.enumerated() {
            let evolution = CoherentNoise.fractal(
                at: time * 0.11 + cloud.phase + lobe.evolutionPhase,
                seed: CoherentNoise.derivedSeed(seed, channel: 0x4C_4F_42_45 + UInt64(index)),
                octaves: 3,
                persistence: 0.50
            )
            let opticalDepth = columnOpticalDepth * lobe.opticalDepthScale
            let extinction = InkNightCloudPhysics.extinction(forOpticalDepth: opticalDepth)
            let center = CGPoint(
                x: bandCenter.x + bandWidth * (lobe.positionX + CGFloat(evolution) * 0.012),
                y: bandCenter.y + bandHeight * (lobe.positionY + CGFloat(evolution) * 0.025)
            )
            let mask = BackgroundSceneFrame.SoftMask(
                center: center,
                size: CGSize(
                    width: bandWidth * (lobe.width + CGFloat(evolution) * 0.018),
                    height: bandHeight * (lobe.height - CGFloat(evolution) * 0.025)
                ),
                angle: cloud.angle + lobe.angle + CGFloat(localWave) * 0.018,
                shape: .ellipse,
                color: palette.cloud,
                opacity: extinction,
                softness: min(size.width, size.height)
                    * (0.024 + lobe.softness * 0.012 + CGFloat(0.5 + localWave * 0.5) * 0.012),
                blendMode: .normal,
                role: .lightOccluder,
                bodyOpacity: 0.018 + extinction * 0.07
            )
            primitives.append(.softMask(mask))
        }
    }

    private func wrappedProgress(_ value: Double) -> Double {
        value - floor(value)
    }
}

private extension InkNightCloudOcclusionModel {
    struct CloudBand: Sendable {
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

    struct CloudLobe: Sendable {
        let positionX: CGFloat
        let positionY: CGFloat
        let width: CGFloat
        let height: CGFloat
        let angle: CGFloat
        let opticalDepthScale: Double
        let softness: CGFloat
        let evolutionPhase: Double
    }

    /// A thin leading edge, dense core, and trailing shoulder form one coherent cloud mass.
    static let lobes: [CloudLobe] = [
        CloudLobe(
            positionX: -0.27, positionY: 0.08, width: 0.58, height: 0.68, angle: -0.035,
            opticalDepthScale: 0.52, softness: 0.72, evolutionPhase: 0.4
        ),
        CloudLobe(
            positionX: 0, positionY: -0.07, width: 0.68, height: 1.0, angle: 0.012,
            opticalDepthScale: 1.0, softness: 1.0, evolutionPhase: 2.1
        ),
        CloudLobe(
            positionX: 0.29, positionY: 0.10, width: 0.55, height: 0.74, angle: 0.044,
            opticalDepthScale: 0.68, softness: 0.82, evolutionPhase: 4.6
        )
    ]

    /// Lower bands advect faster than upper bands, preserving atmospheric parallax.
    static let clouds: [CloudBand] = [
        CloudBand(
            positionY: 0.20, width: 0.92, height: 0.16, angle: -0.11,
            phase: 0.08, speed: 0.014, edgeFrequency: 0.31, verticalDrift: 0.030, density: 0.58
        ),
        CloudBand(
            positionY: 0.39, width: 1.02, height: 0.20, angle: -0.07,
            phase: 0.36, speed: 0.018, edgeFrequency: 0.24, verticalDrift: 0.040, density: 0.72
        ),
        CloudBand(
            positionY: 0.61, width: 0.96, height: 0.18, angle: -0.14,
            phase: 0.61, speed: 0.024, edgeFrequency: 0.28, verticalDrift: 0.032, density: 0.64
        ),
        CloudBand(
            positionY: 0.79, width: 0.86, height: 0.15, angle: -0.09,
            phase: 0.84, speed: 0.030, edgeFrequency: 0.35, verticalDrift: 0.025, density: 0.52
        )
    ]
}
