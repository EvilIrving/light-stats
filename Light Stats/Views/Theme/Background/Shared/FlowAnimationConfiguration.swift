//
//  FlowAnimationConfiguration.swift
//  Light Stats
//

import CoreGraphics
import Foundation

struct FlowAnimationConfiguration: Equatable, Sendable {
    let framesPerSecond: Double
    let pauseThreshold: Double
    let phaseTravelRate: CGFloat
    let slowBandFrequency: CGFloat
    let slowBandStrength: CGFloat
    let detailBandFrequency: CGFloat
    let detailBandPhase: CGFloat
    let detailBandStrength: CGFloat
}
