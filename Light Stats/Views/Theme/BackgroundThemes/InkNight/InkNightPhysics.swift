//
//  InkNightPhysics.swift
//  Light Stats
//

import CoreGraphics
import Foundation

/// Theme-local point-source projection used by the light and cloud occlusion models.
enum InkNightPhysics {
    /// The nominal traversal supplies momentum; coherent phase drift prevents a closed orbit.
    static let nominalTraversalDuration: TimeInterval = 47

    struct LunarState: Sendable {
        let source: CGPoint
        let haloCenter: CGPoint
        let haloRadius: CGFloat
        let target: CGPoint
        let sourceWidth: CGFloat
        let targetWidth: CGFloat
        let intensity: Double
        let haloIntensity: Double
    }

    static func lunarState(time: TimeInterval, size: CGSize, seed: UInt64 = 0) -> LunarState {
        let orbitSeed = CoherentNoise.derivedSeed(seed, channel: 0x4C_55_4E_41_52)
        let phaseDrift = CoherentNoise.fractal(
            at: time * 0.043,
            seed: orbitSeed,
            octaves: 3,
            persistence: 0.49
        ) * 0.62
        let phase = CGFloat(time * 2 * Double.pi / nominalTraversalDuration + phaseDrift)
        let wander = CoherentNoise.fractal(
            at: time * 0.067,
            seed: CoherentNoise.derivedSeed(orbitSeed, channel: 1),
            octaves: 4,
            persistence: 0.52
        )
        let altitude = CoherentNoise.fractal(
            at: time * 0.039,
            seed: CoherentNoise.derivedSeed(orbitSeed, channel: 2),
            octaves: 3,
            persistence: 0.48
        )
        let source = CGPoint(
            x: size.width * (0.5 + sin(phase) * 0.27 + CGFloat(wander) * 0.07),
            y: size.height * (-0.28 + cos(phase) * 0.030 + CGFloat(altitude) * 0.018)
        )
        let aperture = CGPoint(
            x: size.width * (0.5 + CGFloat(wander) * 0.035),
            y: size.height * (0.14 + CGFloat(altitude) * 0.012)
        )
        let targetY = size.height * 1.12
        let projectionScale = (targetY - aperture.y) / max(aperture.y - source.y, 1)
        let target = CGPoint(
            x: aperture.x + (aperture.x - source.x) * projectionScale,
            y: targetY
        )
        let propagationDistance = max(hypot(target.x - source.x, target.y - source.y), 1)
        let sourceWidth = max(size.width * 0.075, 42)
        let targetWidth = sourceWidth + propagationDistance * 2 * tan(0.125)
        let referenceDistance = size.height * 1.42
        let falloff = pow(referenceDistance / propagationDistance, 2)
        let directLightTransmission = apparentLightTransmission(at: time, seed: seed)
        let haloPulse = CoherentNoise.fractal(
            at: time * 0.093,
            seed: CoherentNoise.derivedSeed(orbitSeed, channel: 3),
            octaves: 3,
            persistence: 0.54
        )
        return LunarState(
            source: source,
            haloCenter: aperture,
            haloRadius: max(size.width, size.height) * (0.17 + CGFloat(haloPulse) * 0.018),
            target: target,
            sourceWidth: sourceWidth,
            targetWidth: targetWidth,
            intensity: 0.50 * min(max(falloff, 0.80), 1.04) * directLightTransmission,
            haloIntensity: min(max(0.19 + haloPulse * 0.060, 0.12), 0.29)
        )
    }

    static func apparentLightTransmission(at time: TimeInterval, seed: UInt64 = 0) -> Double {
        let mistSeed = CoherentNoise.derivedSeed(seed, channel: 0x4D_49_53_54)
        let mist = CoherentNoise.fractal(
            at: time * 0.078,
            seed: mistSeed,
            octaves: 4,
            persistence: 0.51
        )
        let veil = CoherentNoise.value(
            at: time * 0.23,
            seed: CoherentNoise.derivedSeed(mistSeed, channel: 1)
        )
        return min(max(0.81 + mist * 0.15 + veil * 0.07, 0.56), 1)
    }
}
