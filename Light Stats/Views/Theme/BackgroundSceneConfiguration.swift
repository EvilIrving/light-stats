//
//  BackgroundSceneConfiguration.swift
//  Light Stats
//

import Foundation

struct BackgroundSceneConfiguration: Equatable, Sendable {
    let intensity: Double
    let sceneSeed: UInt64

    init(intensity: Double, sceneSeed: UInt64 = 0) {
        self.sceneSeed = sceneSeed
        guard intensity.isFinite else {
            self.intensity = 0
            return
        }
        self.intensity = min(max(intensity, 0), 1)
    }
}
