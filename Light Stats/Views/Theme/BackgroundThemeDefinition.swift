//
//  BackgroundThemeDefinition.swift
//  Light Stats
//

import CoreGraphics
import Foundation

/// Theme-owned composition of scene, occlusion, readability, and material capabilities.
struct BackgroundThemeDefinition {
    let identifier: String
    let sceneModel: any BackgroundSceneModel
    let occlusionModel: any BackgroundOcclusionModel
    let readabilityPolicy: any BackgroundReadabilityPolicy
    let materialEffects: [AnyBackgroundMaterialEffect]

    var materialIdentifiers: [String] {
        materialEffects.map(\.id)
    }

    func makeFrame(
        time: TimeInterval,
        size: CGSize,
        configuration: BackgroundSceneConfiguration
    ) -> BackgroundSceneFrame {
        sceneModel
            .makeFrame(time: time, size: size, configuration: configuration)
            .appending(
                occlusionModel.makeOcclusions(
                    time: time,
                    size: size,
                    configuration: configuration
                )
            )
            .appending(
                readabilityPolicy.makeRegions(
                    size: size,
                    configuration: configuration
                )
            )
    }
}
