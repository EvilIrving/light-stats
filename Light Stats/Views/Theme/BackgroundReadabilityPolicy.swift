//
//  BackgroundReadabilityPolicy.swift
//  Light Stats
//

import CoreGraphics

protocol BackgroundReadabilityPolicy: Sendable {
    func makeRegions(
        size: CGSize,
        configuration: BackgroundSceneConfiguration
    ) -> [BackgroundSceneFrame.Primitive]
}
