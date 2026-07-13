//
//  InkNightCloudOcclusionModel.swift
//  Light Stats
//

import CoreGraphics
import Foundation

/// Layered ink washes with independent advection, breakup, density, and silver-edge shimmer.
struct InkNightCloudOcclusionModel: BackgroundOcclusionModel {
    let palette: InkNightBackgroundTheme.Palette

    func makeOcclusions(
        time: TimeInterval,
        size: CGSize,
        configuration: BackgroundSceneConfiguration
    ) -> [BackgroundSceneFrame.Primitive] {
        let seed = CoherentNoise.derivedSeed(configuration.sceneSeed, channel: 0x43_4C_4F_55_44)
        let coverage = cloudCoverage(time: time, seed: seed)
        var primitives: [BackgroundSceneFrame.Primitive] = []
        primitives.reserveCapacity(Self.layers.count * (Self.strokes.count + Self.silverEdges.count))

        for (index, layer) in Self.layers.enumerated() {
            let layerSeed = CoherentNoise.derivedSeed(seed, channel: UInt64(index) + 1)
            let state = layerState(
                for: layer,
                time: time,
                size: size,
                seed: layerSeed
            )
            appendInkStrokes(
                for: layer,
                state: state,
                time: time,
                size: size,
                coverage: coverage,
                seed: layerSeed,
                to: &primitives
            )
            appendSilverEdges(
                for: layer,
                state: state,
                time: time,
                size: size,
                seed: layerSeed,
                to: &primitives
            )
        }
        return primitives
    }

    private func cloudCoverage(time: TimeInterval, seed: UInt64) -> Double {
        let broadWeather = CoherentNoise.fractal(
            at: time * 0.031,
            seed: seed,
            octaves: 4,
            persistence: 0.55
        )
        let localWeather = CoherentNoise.fractal(
            at: time * 0.087,
            seed: CoherentNoise.derivedSeed(seed, channel: 0x57_45_41_54_48_45_52),
            octaves: 3,
            persistence: 0.48
        )
        return min(max(0.52 + broadWeather * 0.31 + localWeather * 0.12, 0.18), 0.92)
    }

    private func layerState(
        for layer: CloudLayer,
        time: TimeInterval,
        size: CGSize,
        seed: UInt64
    ) -> LayerState {
        let velocity = CoherentNoise.fractal(
            at: time * 0.026 + layer.phase,
            seed: seed,
            octaves: 3,
            persistence: 0.48
        )
        let sessionOffset = CoherentNoise.value(at: layer.phase * 7.1, seed: seed) * 0.24
        let progress = wrappedProgress(
            time * layer.speed + layer.phase + sessionOffset + velocity * 0.09
        )
        let edgeMotion = CoherentNoise.fractal(
            at: time * layer.edgeFrequency + layer.phase,
            seed: CoherentNoise.derivedSeed(seed, channel: 0x45_44_47_45),
            octaves: 3,
            persistence: 0.54
        )
        let breathing = CoherentNoise.fractal(
            at: time * 0.071 + layer.phase * 3,
            seed: CoherentNoise.derivedSeed(seed, channel: 0x42_52_45_41_54_48),
            octaves: 4,
            persistence: 0.50
        )
        let width = size.width * layer.width * (1 + CGFloat(breathing) * 0.045)
        let height = size.height * layer.height * (1 + CGFloat(edgeMotion) * 0.07)
        let center = CGPoint(
            x: size.width * (-0.52 + CGFloat(progress) * 2.04),
            y: size.height * (layer.positionY + CGFloat(edgeMotion) * layer.verticalDrift)
        )
        return LayerState(center: center, width: width, height: height, edgeMotion: edgeMotion)
    }

    private func appendInkStrokes(
        for layer: CloudLayer,
        state: LayerState,
        time: TimeInterval,
        size: CGSize,
        coverage: Double,
        seed: UInt64,
        to primitives: inout [BackgroundSceneFrame.Primitive]
    ) {
        for (index, stroke) in Self.strokes.enumerated() {
            let strokeSeed = CoherentNoise.derivedSeed(seed, channel: 0x53_54_52_4F_4B_45 + UInt64(index))
            let evolution = CoherentNoise.fractal(
                at: time * stroke.evolutionSpeed + stroke.phase + layer.phase,
                seed: strokeSeed,
                octaves: 3,
                persistence: 0.52
            )
            let breakup = CoherentNoise.fractal(
                at: time * stroke.breakupSpeed + stroke.phase * 2.3,
                seed: CoherentNoise.derivedSeed(strokeSeed, channel: 1),
                octaves: 2,
                persistence: 0.61
            )
            let opticalDepth = max(
                (layer.density + coverage * 0.58 + state.edgeMotion * 0.08)
                    * stroke.opticalDepthScale * (1 + breakup * 0.15),
                0.08
            )
            let extinction = InkNightCloudPhysics.extinction(forOpticalDepth: opticalDepth)
            let mask = BackgroundSceneFrame.SoftMask(
                center: CGPoint(
                    x: state.center.x + state.width * (stroke.positionX + CGFloat(evolution) * 0.018),
                    y: state.center.y + state.height * (stroke.positionY + CGFloat(breakup) * 0.045)
                ),
                size: CGSize(
                    width: state.width * max(stroke.width + CGFloat(evolution) * 0.028, 0.12),
                    height: state.height * max(stroke.height + CGFloat(breakup) * 0.055, 0.16)
                ),
                angle: layer.angle + stroke.angle + CGFloat(state.edgeMotion) * 0.025,
                shape: .inkWash,
                color: palette.cloud,
                opacity: extinction,
                softness: min(size.width, size.height)
                    * (0.007 + stroke.softness * 0.006 + CGFloat(0.5 + breakup * 0.5) * 0.003),
                blendMode: .normal,
                role: .lightOccluder,
                bodyOpacity: 0.025 + extinction * 0.16
            )
            primitives.append(.softMask(mask))
        }
    }

    private func appendSilverEdges(
        for layer: CloudLayer,
        state: LayerState,
        time: TimeInterval,
        size: CGSize,
        seed: UInt64,
        to primitives: inout [BackgroundSceneFrame.Primitive]
    ) {
        for (index, edge) in Self.silverEdges.enumerated() {
            let edgeSeed = CoherentNoise.derivedSeed(seed, channel: 0x53_49_4C_56_45_52 + UInt64(index))
            let shimmer = CoherentNoise.fractal(
                at: time * edge.shimmerSpeed + edge.phase + layer.phase,
                seed: edgeSeed,
                octaves: 3,
                persistence: 0.58
            )
            let strength = pow((shimmer + 1) / 2, 2.4)
            let mask = BackgroundSceneFrame.SoftMask(
                center: CGPoint(
                    x: state.center.x + state.width * (edge.positionX + CGFloat(shimmer) * 0.010),
                    y: state.center.y + state.height * (edge.positionY + CGFloat(shimmer) * 0.018)
                ),
                size: CGSize(
                    width: state.width * (edge.width + CGFloat(strength) * 0.055),
                    height: state.height * (edge.height + CGFloat(strength) * 0.025)
                ),
                angle: layer.angle + edge.angle + CGFloat(shimmer) * 0.018,
                shape: .inkWash,
                color: palette.cloudSilver,
                opacity: 0.045 + strength * 0.28,
                softness: min(size.width, size.height) * 0.003,
                blendMode: .plusLighter,
                role: .surfaceHighlight
            )
            primitives.append(.softMask(mask))
        }
    }

    private func wrappedProgress(_ value: Double) -> Double {
        value - floor(value)
    }
}

private extension InkNightCloudOcclusionModel {
    struct LayerState: Sendable {
        let center: CGPoint
        let width: CGFloat
        let height: CGFloat
        let edgeMotion: Double
    }

    struct CloudLayer: Sendable {
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

    struct InkStroke: Sendable {
        let positionX: CGFloat
        let positionY: CGFloat
        let width: CGFloat
        let height: CGFloat
        let angle: CGFloat
        let opticalDepthScale: Double
        let softness: CGFloat
        let phase: Double
        let evolutionSpeed: Double
        let breakupSpeed: Double
    }

    struct SilverEdge: Sendable {
        let positionX: CGFloat
        let positionY: CGFloat
        let width: CGFloat
        let height: CGFloat
        let angle: CGFloat
        let phase: Double
        let shimmerSpeed: Double
    }

    static let strokes: [InkStroke] = [
        InkStroke(
            positionX: -0.31, positionY: 0.06, width: 0.52, height: 0.54, angle: -0.045,
            opticalDepthScale: 0.34, softness: 1.15, phase: 0.2, evolutionSpeed: 0.10, breakupSpeed: 0.23
        ),
        InkStroke(
            positionX: -0.18, positionY: -0.09, width: 0.62, height: 0.75, angle: -0.018,
            opticalDepthScale: 0.62, softness: 0.82, phase: 1.1, evolutionSpeed: 0.13, breakupSpeed: 0.28
        ),
        InkStroke(
            positionX: 0, positionY: 0, width: 0.72, height: 1.0, angle: 0.012,
            opticalDepthScale: 1.25, softness: 0.55, phase: 2.4, evolutionSpeed: 0.09, breakupSpeed: 0.31
        ),
        InkStroke(
            positionX: 0.20, positionY: 0.08, width: 0.58, height: 0.72, angle: 0.038,
            opticalDepthScale: 0.76, softness: 0.72, phase: 3.3, evolutionSpeed: 0.15, breakupSpeed: 0.26
        ),
        InkStroke(
            positionX: 0.36, positionY: -0.04, width: 0.44, height: 0.48, angle: 0.064,
            opticalDepthScale: 0.42, softness: 1.08, phase: 4.7, evolutionSpeed: 0.12, breakupSpeed: 0.34
        ),
        InkStroke(
            positionX: -0.04, positionY: -0.31, width: 0.42, height: 0.34, angle: -0.030,
            opticalDepthScale: 0.52, softness: 0.90, phase: 5.6, evolutionSpeed: 0.18, breakupSpeed: 0.39
        ),
        InkStroke(
            positionX: 0.08, positionY: 0.32, width: 0.50, height: 0.30, angle: 0.026,
            opticalDepthScale: 0.58, softness: 0.96, phase: 6.8, evolutionSpeed: 0.16, breakupSpeed: 0.36
        )
    ]

    static let silverEdges: [SilverEdge] = [
        SilverEdge(
            positionX: -0.19, positionY: -0.34, width: 0.34, height: 0.11,
            angle: -0.025, phase: 0.7, shimmerSpeed: 0.37
        ),
        SilverEdge(
            positionX: 0.23, positionY: -0.22, width: 0.26, height: 0.085,
            angle: 0.035, phase: 3.1, shimmerSpeed: 0.49
        )
    ]

    /// Distinct speeds and phases prevent the stacked atmosphere from returning as one cycle.
    static let layers: [CloudLayer] = [
        CloudLayer(
            positionY: 0.16, width: 0.96, height: 0.13, angle: -0.12,
            phase: 0.06, speed: 0.009, edgeFrequency: 0.17, verticalDrift: 0.026, density: 0.42
        ),
        CloudLayer(
            positionY: 0.32, width: 1.08, height: 0.17, angle: -0.07,
            phase: 0.27, speed: 0.013, edgeFrequency: 0.23, verticalDrift: 0.036, density: 0.64
        ),
        CloudLayer(
            positionY: 0.50, width: 1.16, height: 0.19, angle: -0.10,
            phase: 0.49, speed: 0.017, edgeFrequency: 0.19, verticalDrift: 0.042, density: 0.78
        ),
        CloudLayer(
            positionY: 0.69, width: 1.04, height: 0.16, angle: -0.15,
            phase: 0.71, speed: 0.022, edgeFrequency: 0.27, verticalDrift: 0.034, density: 0.58
        ),
        CloudLayer(
            positionY: 0.84, width: 0.90, height: 0.12, angle: -0.09,
            phase: 0.90, speed: 0.028, edgeFrequency: 0.33, verticalDrift: 0.024, density: 0.36
        )
    ]
}
