//
//  InkNightPhysics.swift
//  Light Stats
//

import CoreGraphics
import Foundation

/// Theme-local point-source projection used by the light and cloud occlusion models.
enum InkNightPhysics {
    /// At maximum dynamics, the lunar time-lapse completes during one deliberate inspection.
    static let orbitPeriod: TimeInterval = 28

    struct LunarState: Sendable {
        let source: CGPoint
        let target: CGPoint
        let sourceWidth: CGFloat
        let targetWidth: CGFloat
        let intensity: Double
    }

    static func lunarState(time: TimeInterval, size: CGSize) -> LunarState {
        let phase = CGFloat(time * 2 * Double.pi / orbitPeriod)
        let source = CGPoint(
            x: size.width * (0.5 + sin(phase) * 0.34),
            y: size.height * (-0.30 + cos(phase) * 0.045)
        )
        let aperture = CGPoint(x: size.width * 0.5, y: size.height * 0.15)
        let targetY = size.height * 1.12
        let projectionScale = (targetY - aperture.y) / max(aperture.y - source.y, 1)
        let target = CGPoint(
            x: aperture.x + (aperture.x - source.x) * projectionScale,
            y: targetY
        )
        let propagationDistance = max(hypot(target.x - source.x, target.y - source.y), 1)
        let sourceWidth = max(size.width * 0.10, 48)
        let targetWidth = sourceWidth + propagationDistance * 2 * tan(0.14)
        let referenceDistance = size.height * 1.42
        let falloff = pow(referenceDistance / propagationDistance, 2)
        return LunarState(
            source: source,
            target: target,
            sourceWidth: sourceWidth,
            targetWidth: targetWidth,
            intensity: 0.68 * min(max(falloff, 0.80), 1.04)
        )
    }
}
