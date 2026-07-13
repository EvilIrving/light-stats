//
//  SunGoldPhysics.swift
//  Light Stats
//

import CoreGraphics
import Foundation

/// Theme-local physical state shared by the light source and its cast shadows.
enum SunGoldPhysics {
    /// The nominal traversal supplies momentum; coherent phase drift prevents a closed orbit.
    static let nominalTraversalDuration: TimeInterval = 34

    struct SolarState: Sendable {
        let center: CGPoint
        let brightness: Double
        let shadowDirection: CGFloat
    }

    static func solarState(time: TimeInterval, size: CGSize, seed: UInt64 = 0) -> SolarState {
        let orbitSeed = CoherentNoise.derivedSeed(seed, channel: 0x53_4F_4C_41_52)
        let phaseDrift = CoherentNoise.fractal(
            at: time * 0.073,
            seed: orbitSeed,
            octaves: 3,
            persistence: 0.46
        ) * 0.82
        let phase = CGFloat(time * 2 * Double.pi / nominalTraversalDuration + phaseDrift)
        let elevation = (1 - cos(phase)) / 2
        let directLightTransmission = apparentLightTransmission(at: time, seed: seed)
        let center = CGPoint(
            x: size.width * (0.5 + sin(phase) * 0.92),
            y: size.height * (0.285 - elevation * 0.11)
        )
        return SolarState(
            center: center,
            brightness: (0.74 + Double(elevation) * 0.14) * directLightTransmission,
            shadowDirection: -sin(phase)
        )
    }

    static func apparentLightTransmission(at time: TimeInterval, seed: UInt64 = 0) -> Double {
        let luminositySeed = CoherentNoise.derivedSeed(seed, channel: 0x48_41_5A_45)
        let broadHaze = CoherentNoise.fractal(
            at: time * 0.095,
            seed: luminositySeed,
            octaves: 4,
            persistence: 0.48
        )
        let thinHaze = CoherentNoise.value(
            at: time * 0.31,
            seed: CoherentNoise.derivedSeed(luminositySeed, channel: 1)
        )
        return min(max(0.79 + broadHaze * 0.17 + thinHaze * 0.06, 0.56), 1)
    }

    static func gust(at time: TimeInterval, seed: UInt64 = 0) -> CGFloat {
        let gustSeed = CoherentNoise.derivedSeed(seed, channel: 0x47_55_53_54)
        let direction = CoherentNoise.fractal(
            at: time * 0.39,
            seed: gustSeed,
            octaves: 3,
            persistence: 0.55
        )
        let envelopeValue = CoherentNoise.value(
            at: time * 0.105,
            seed: CoherentNoise.derivedSeed(gustSeed, channel: 1)
        )
        let envelope = 0.24 + pow((envelopeValue + 1) / 2, 2) * 0.92
        return CGFloat(min(max(direction * envelope, -1), 1))
    }
}
