//
//  CoherentNoise.swift
//  Light Stats
//

import Foundation

/// Deterministic, continuous noise for organic motion without a short repeating period.
enum CoherentNoise {
    static func value(at position: Double, seed: UInt64) -> Double {
        guard position.isFinite else { return 0 }
        let lowerPosition = floor(position)
        let lower = Int64(lowerPosition)
        let upper = lower == Int64.max ? lower : lower + 1
        let fraction = position - lowerPosition
        let blend = fraction * fraction * fraction * (fraction * (fraction * 6 - 15) + 10)
        let lowerValue = randomValue(at: lower, seed: seed)
        let upperValue = randomValue(at: upper, seed: seed)
        return lowerValue + (upperValue - lowerValue) * blend
    }

    static func fractal(
        at position: Double,
        seed: UInt64,
        octaves: Int = 3,
        persistence: Double = 0.52
    ) -> Double {
        guard octaves > 0 else { return 0 }
        var frequency = 1.0
        var amplitude = 1.0
        var total = 0.0
        var amplitudeTotal = 0.0
        for octave in 0..<octaves {
            total += value(
                at: position * frequency,
                seed: derivedSeed(seed, channel: UInt64(octave))
            ) * amplitude
            amplitudeTotal += amplitude
            frequency *= 2.03
            amplitude *= persistence
        }
        return total / amplitudeTotal
    }

    static func derivedSeed(_ seed: UInt64, channel: UInt64) -> UInt64 {
        mix(seed &+ channel &* 0x9E37_79B9_7F4A_7C15)
    }

    private static func randomValue(at lattice: Int64, seed: UInt64) -> Double {
        let bits = mix(UInt64(bitPattern: lattice) &+ seed)
        let unitValue = Double(bits >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return unitValue * 2 - 1
    }

    private static func mix(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
