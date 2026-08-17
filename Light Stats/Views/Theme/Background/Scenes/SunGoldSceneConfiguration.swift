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
        canvas: Color(red: 0.10, green: 0.06, blue: 0.05),
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
            meshBase: Color(red: 0.16, green: 0.08, blue: 0.07),
            primary: Color(red: 0.42, green: 0.20, blue: 0.18),
            secondary: Color(red: 0.78, green: 0.40, blue: 0.30),
            highlight: Color(red: 0.90, green: 0.72, blue: 0.58),
            primaryGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.18,
                opacity: 1,
                motionScale: 1
            ),
            ambientGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.18,
                opacity: 0.6,
                motionScale: 1
            ),
            primaryRibbon: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.08,
                opacity: 1,
                motionScale: 1
            ),
            secondaryRibbon: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.12,
                opacity: 0.5,
                motionScale: 1
            ),
            highlightGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.14,
                opacity: 0.55,
                motionScale: 1
            )
        ),
        veil: ReadingVeilConfiguration(
            centerColor: Color(red: 0.06, green: 0.03, blue: 0.02),
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
            warmth: 0.5,
            warmthOpacityRatio: 0.14,
            warmTint: Color(red: 0.92, green: 0.62, blue: 0.42)
        )
    )
}
