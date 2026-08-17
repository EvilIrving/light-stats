//
//  LightFieldLayerConfiguration.swift
//  Light Stats
//

import CoreGraphics
import Foundation

struct LightFieldLayerConfiguration: Equatable, Sendable {
    let isEnabled: Bool
    let blurRadiusScale: CGFloat
    let opacity: Double
    let motionScale: CGFloat
}
