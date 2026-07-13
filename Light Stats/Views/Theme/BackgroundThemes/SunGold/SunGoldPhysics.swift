//
//  SunGoldPhysics.swift
//  Light Stats
//

import CoreGraphics
import Foundation

/// Theme-local physical state shared by the light source and its cast shadows.
enum SunGoldPhysics {
    /// At maximum dynamics, the complete time-lapse orbit is visible within one short inspection.
    static let orbitPeriod: TimeInterval = 24

    struct SolarState: Sendable {
        let center: CGPoint
        let brightness: Double
        let shadowDirection: CGFloat
    }

    static func solarState(time: TimeInterval, size: CGSize) -> SolarState {
        let phase = CGFloat(time * 2 * Double.pi / orbitPeriod)
        let elevation = (1 - cos(phase)) / 2
        let center = CGPoint(
            x: size.width * (0.5 + sin(phase) * 0.92),
            y: size.height * (0.285 - elevation * 0.11)
        )
        return SolarState(
            center: center,
            brightness: 0.76 + Double(elevation) * 0.10,
            shadowDirection: -sin(phase)
        )
    }

    static func gust(at time: TimeInterval) -> CGFloat {
        let primary = sin(CGFloat(time) * 2 * .pi / 7.5) * 0.68
        let secondary = sin(CGFloat(time) * 2 * .pi / 3.1 + 1.2) * 0.32
        return primary + secondary
    }
}
