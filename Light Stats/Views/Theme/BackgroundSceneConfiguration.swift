//
//  BackgroundSceneConfiguration.swift
//  Light Stats
//

import Foundation

struct BackgroundSceneConfiguration: Equatable, Sendable {
    let intensity: Double

    init(intensity: Double) {
        guard intensity.isFinite else {
            self.intensity = 0
            return
        }
        self.intensity = min(max(intensity, 0), 1)
    }
}
