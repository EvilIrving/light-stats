//
//  SunGoldSceneConfiguration.swift
//  Light Stats
//

import SwiftUI

struct SunGoldSceneConfiguration {
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
        let sunDisk: LightFieldLayerConfiguration
        let primaryGlow: LightFieldLayerConfiguration
        let ambientGlow: LightFieldLayerConfiguration
        let primaryRibbon: LightFieldLayerConfiguration
        let secondaryRibbon: LightFieldLayerConfiguration
        let highlightGlow: LightFieldLayerConfiguration
    }

    let canvas: Color
    let flow: FlowAnimationConfiguration
    let motion: Motion
    let lightField: LightField
    let veil: ReadingVeilConfiguration
    let grain: GrainOverlayConfiguration

    static let defaults = SunGoldSceneConfiguration(
        canvas: Color(red: 0.10, green: 0.018, blue: 0.004),
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
            amplitudeBase: 0.68,
            amplitudeSpan: 0.32,
            phaseOffset: 0.45,
            horizontalPrimary: 0.105,
            horizontalSecondary: 0.038,
            verticalPrimary: 0.065,
            verticalSecondary: 0.028
        ),
        lightField: LightField(
            meshBase: Color(red: 0.22, green: 0.035, blue: 0.008),
            primary: Color(red: 0.54, green: 0.11, blue: 0.018),
            secondary: Color(red: 0.94, green: 0.32, blue: 0.045),
            highlight: Color(red: 1.0, green: 0.78, blue: 0.30),
            sunDisk: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.035,
                opacity: 0.48,
                motionScale: 0.35
            ),
            primaryGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.14,
                opacity: 1,
                motionScale: 1
            ),
            ambientGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.20,
                opacity: 0.82,
                motionScale: 1
            ),
            primaryRibbon: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.07,
                opacity: 1,
                motionScale: 1
            ),
            secondaryRibbon: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.10,
                opacity: 0.72,
                motionScale: 1
            ),
            highlightGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.11,
                opacity: 0.80,
                motionScale: 1
            )
        ),
        veil: ReadingVeilConfiguration(
            centerColor: Color(red: 0.10, green: 0.015, blue: 0.002),
            innerOpacity: 0.22,
            middleOpacity: 0.10,
            outerOpacity: 0.02,
            centerX: 0.5,
            centerY: 0.44,
            horizontalFollow: 0.35,
            verticalFollow: 0.3,
            startRadiusScale: 0.06,
            endRadiusScale: 0.84
        ),
        grain: GrainOverlayConfiguration(
            opacity: 0.26,
            scale: 1,
            bodyOpacityRatio: 0.35,
            warmth: 0.9,
            warmthOpacityRatio: 0.20,
            warmTint: Color(red: 1.0, green: 0.58, blue: 0.20)
        )
    )
}
