//
//  BackgroundOcclusionModel.swift
//  Light Stats
//

import CoreGraphics
import Foundation

protocol BackgroundOcclusionModel: Sendable {
    func makeOcclusions(
        time: TimeInterval,
        size: CGSize,
        configuration: BackgroundSceneConfiguration
    ) -> [BackgroundSceneFrame.Primitive]
}
