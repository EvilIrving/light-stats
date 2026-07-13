//
//  BackgroundSceneModel.swift
//  Light Stats
//

import CoreGraphics
import Foundation

protocol BackgroundSceneModel: Sendable {
    func makeFrame(
        time: TimeInterval,
        size: CGSize,
        configuration: BackgroundSceneConfiguration
    ) -> BackgroundSceneFrame
}
