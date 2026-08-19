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
        /// Warm bar light (amber) — the dominant glow, like backlit shelves.
        let warm: Color
        /// Cool neon accent (teal) — a single neon sign against the warmth.
        let cool: Color
        let amber: Color
        let warmGlow: LightFieldLayerConfiguration
        let coolGlow: LightFieldLayerConfiguration
        let warmTube: LightFieldLayerConfiguration
        let coolTube: LightFieldLayerConfiguration
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
        canvas: Color(red: 0.016, green: 0.013, blue: 0.018),
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
            meshBase: Color(red: 0.052, green: 0.038, blue: 0.028),
            warm: Color(red: 1.0, green: 0.58, blue: 0.20),
            cool: Color(red: 0.05, green: 0.76, blue: 0.70),
            amber: Color(red: 1.0, green: 0.74, blue: 0.36),
            warmGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.17,
                opacity: 0.88,
                motionScale: 1
            ),
            coolGlow: LightFieldLayerConfiguration(
                isEnabled: true,
                blurRadiusScale: 0.18,
                opacity: 0.60,
                motionScale: 1
            ),
            warmTube: LightFieldLayerConfiguration(
                isEnabled: false,
                blurRadiusScale: 0.045,
                opacity: 0.80,
                motionScale: 0.72
            ),
            coolTube: LightFieldLayerConfiguration(
                isEnabled: false,
                blurRadiusScale: 0.055,
                opacity: 0.64,
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
                opacity: 0.70,
                motionScale: 0.52
            )
        ),
        veil: ReadingVeilConfiguration(
            centerColor: Color(red: 0.012, green: 0.008, blue: 0.012),
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
            warmTint: Color(red: 1.0, green: 0.66, blue: 0.30)
        )
    )
}
