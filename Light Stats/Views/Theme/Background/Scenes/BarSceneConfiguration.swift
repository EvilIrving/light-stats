//
//  BarSceneConfiguration.swift
//  Light Stats
//

import SwiftUI

struct BarSceneConfiguration {
    struct Motion {
        let amplitudeBase: CGFloat
        let amplitudeSpan: CGFloat
        let phaseOffset: CGFloat
        let horizontalPrimary: CGFloat
        let horizontalSecondary: CGFloat
        let verticalPrimary: CGFloat
        let verticalSecondary: CGFloat
    }

    struct LightField {
        let meshBase: Color
        let red: Color
        let green: Color
        let amber: Color
        let redGlow: LightFieldLayerConfiguration
        let greenGlow: LightFieldLayerConfiguration
        let redTube: LightFieldLayerConfiguration
        let greenTube: LightFieldLayerConfiguration
        let lampGlow: LightFieldLayerConfiguration
        let counterReflection: LightFieldLayerConfiguration
    }

    let canvas: Color
    let flow: FlowAnimationConfiguration
    let motion: Motion
    let lightField: LightField
    let veil: ReadingVeilConfiguration
    let grain: GrainOverlayConfiguration

    static let defaults = BarSceneConfiguration(
        canvas: Color(red: 0.018, green: 0.004, blue: 0.012),
        flow: FlowAnimationConfiguration(
            framesPerSecond: 24,
            pauseThreshold: 0.02,
            phaseTravelRate: .pi / 3.4,
            slowBandFrequency: 0.21,
            slowBandStrength: 0.10,
            detailBandFrequency: 0.43,
            detailBandPhase: 0.9,
            detailBandStrength: 0.05
        ),
        motion: Motion(
            amplitudeBase: 0.34,
            amplitudeSpan: 0.72,
            phaseOffset: 0.8,
            horizontalPrimary: 0.09,
            horizontalSecondary: 0.035,
            verticalPrimary: 0.07,
            verticalSecondary: 0.03
        ),
        lightField: LightField(
            meshBase: Color(red: 0.055, green: 0.008, blue: 0.03),
            red: Color(red: 0.96, green: 0.025, blue: 0.16),
            green: Color(red: 0.015, green: 0.86, blue: 0.38),
            amber: Color(red: 1.0, green: 0.58, blue: 0.16),
            redGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.17,
                opacity: 0.92,
                motionScale: 1
            ),
            greenGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.18,
                opacity: 0.88,
                motionScale: 1
            ),
            redTube: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.045,
                opacity: 0.84,
                motionScale: 0.72
            ),
            greenTube: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.055,
                opacity: 0.86,
                motionScale: 0.78
            ),
            lampGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.035,
                opacity: 0.70,
                motionScale: 0.28
            ),
            counterReflection: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.09,
                opacity: 0.74,
                motionScale: 0.52
            )
        ),
        veil: ReadingVeilConfiguration(
            centerColor: Color(red: 0.012, green: 0.004, blue: 0.012),
            innerOpacity: 0.62,
            middleOpacity: 0.34,
            outerOpacity: 0.08,
            centerX: 0.5,
            centerY: 0.47,
            horizontalFollow: 0.24,
            verticalFollow: 0.2,
            startRadiusScale: 0.05,
            endRadiusScale: 0.78
        ),
        grain: GrainOverlayConfiguration(
            opacity: 0.32,
            scale: 1,
            bodyOpacityRatio: 0.45,
            warmth: 0.32,
            warmthOpacityRatio: 0.16,
            warmTint: Color(red: 1.0, green: 0.42, blue: 0.16)
        )
    )
}
