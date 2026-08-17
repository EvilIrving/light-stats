//
//  InkNightSceneConfiguration.swift
//  Light Stats
//

import SwiftUI

struct InkNightSceneConfiguration {
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
        let primary: Color
        let secondary: Color
        let highlight: Color
        let primaryShaft: LightFieldLayerConfiguration
        let ambientGlow: LightFieldLayerConfiguration
        let primaryBeam: LightFieldLayerConfiguration
        let secondaryBeam: LightFieldLayerConfiguration
        let topGlow: LightFieldLayerConfiguration
        let lowerShade: LightFieldLayerConfiguration
    }

    let canvas: Color
    let flow: FlowAnimationConfiguration
    let motion: Motion
    let lightField: LightField
    let veil: ReadingVeilConfiguration
    let grain: GrainOverlayConfiguration

    static let defaults = InkNightSceneConfiguration(
        canvas: Color(red: 0.03, green: 0.03, blue: 0.04),
        flow: FlowAnimationConfiguration(
            framesPerSecond: 24,
            pauseThreshold: 0.02,
            phaseTravelRate: .pi / 3,
            slowBandFrequency: 0.19,
            slowBandStrength: 0.12,
            detailBandFrequency: 0.37,
            detailBandPhase: 1.2,
            detailBandStrength: 0.06
        ),
        motion: Motion(
            amplitudeBase: 0.35,
            amplitudeSpan: 1.15,
            phaseOffset: 1.35,
            horizontalPrimary: 0.14,
            horizontalSecondary: 0.05,
            verticalPrimary: 0.12,
            verticalSecondary: 0.045
        ),
        lightField: LightField(
            meshBase: Color(red: 0.04, green: 0.04, blue: 0.06),
            primary: Color(red: 0.10, green: 0.10, blue: 0.15),
            secondary: Color(red: 0.22, green: 0.22, blue: 0.36),
            highlight: Color(red: 0.48, green: 0.52, blue: 0.68),
            primaryShaft: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.16,
                opacity: 1,
                motionScale: 1
            ),
            ambientGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.2,
                opacity: 0.4,
                motionScale: 1
            ),
            primaryBeam: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.1,
                opacity: 1,
                motionScale: 1
            ),
            secondaryBeam: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.14,
                opacity: 0.35,
                motionScale: 1
            ),
            topGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.14,
                opacity: 0.45,
                motionScale: 1
            ),
            lowerShade: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0,
                opacity: 1,
                motionScale: 0
            )
        ),
        veil: ReadingVeilConfiguration(
            centerColor: .black,
            innerOpacity: 0.48,
            middleOpacity: 0.24,
            outerOpacity: 0.06,
            centerX: 0.5,
            centerY: 0.48,
            horizontalFollow: 0.35,
            verticalFollow: 0.3,
            startRadiusScale: 0.06,
            endRadiusScale: 0.75
        ),
        grain: GrainOverlayConfiguration(
            opacity: 0.42,
            scale: 1,
            bodyOpacityRatio: 0.55,
            warmth: 0,
            warmthOpacityRatio: 0.14,
            warmTint: Color(red: 0.92, green: 0.62, blue: 0.42)
        )
    )
}
