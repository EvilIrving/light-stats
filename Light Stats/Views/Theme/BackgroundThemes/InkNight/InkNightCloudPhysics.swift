//
//  InkNightCloudPhysics.swift
//  Light Stats
//

import Foundation

/// Beer-Lambert transmission for theme-local cloud optical depth.
enum InkNightCloudPhysics {
    static let extinctionCoefficient = 1.55

    static func transmission(forOpticalDepth opticalDepth: Double) -> Double {
        exp(-max(opticalDepth, 0) * extinctionCoefficient)
    }

    static func extinction(forOpticalDepth opticalDepth: Double) -> Double {
        min(1 - transmission(forOpticalDepth: opticalDepth), 0.995)
    }
}
