//
//  BarScene.swift
//  Light Stats
//

import SwiftUI

struct BarScene: View {
    let input: BarSceneInput
    let configuration: BarSceneConfiguration
    @State private var phaseAnchorDate = Date()
    @State private var phaseAnchor: CGFloat = 0

    init(
        input: BarSceneInput,
        configuration: BarSceneConfiguration = .defaults
    ) {
        self.input = input
        self.configuration = configuration
    }

    private var animationPaused: Bool {
        input.lightFlow < configuration.flow.pauseThreshold
    }

    var body: some View {
        let interval = 1.0 / max(configuration.flow.framesPerSecond, 1)
        TimelineView(.animation(minimumInterval: interval, paused: animationPaused)) { context in
            let phase = Self.phase(
                anchor: phaseAnchor,
                anchorDate: phaseAnchorDate,
                at: context.date,
                lightFlow: input.lightFlow,
                configuration: configuration.flow
            )

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let scale = min(width, height)
                let motion = Self.motionOffset(
                    phase: phase,
                    lightFlow: input.lightFlow,
                    pauseThreshold: configuration.flow.pauseThreshold,
                    width: width,
                    height: height,
                    configuration: configuration.motion
                )

                ZStack {
                    configuration.canvas

                    BarLightField(
                        configuration: configuration.lightField,
                        width: width,
                        height: height,
                        scale: scale,
                        phase: phase,
                        shiftX: motion.x,
                        shiftY: motion.y
                    )
                    .drawingGroup(opaque: true, colorMode: .extendedLinear)

                    ReadingVeilOverlay(
                        configuration: configuration.veil,
                        width: width,
                        height: height,
                        scale: scale,
                        motionOffset: motion
                    )

                    GrainOverlay(
                        configuration: configuration.grain,
                        isEnabled: input.grainEnabled
                    )
                }
                .frame(width: width, height: height)
            }
        }
        .onChange(of: input.lightFlow) { oldLightFlow, _ in
            let now = Date()
            phaseAnchor = Self.phase(
                anchor: phaseAnchor,
                anchorDate: phaseAnchorDate,
                at: now,
                lightFlow: oldLightFlow,
                configuration: configuration.flow
            )
            phaseAnchorDate = now
        }
    }

    static func phase(
        anchor: CGFloat,
        anchorDate: Date,
        at date: Date,
        lightFlow: Double,
        configuration: FlowAnimationConfiguration
    ) -> CGFloat {
        let flowStrength = activeFlowStrength(
            lightFlow,
            pauseThreshold: configuration.pauseThreshold
        )
        guard flowStrength > 0 else { return anchor }
        let elapsed = date.timeIntervalSince(anchorDate)
        let travel = CGFloat(elapsed) * flowStrength * configuration.phaseTravelRate
        let slowBand = sin((anchor + travel) * configuration.slowBandFrequency)
            - sin(anchor * configuration.slowBandFrequency)
        let detailBand = sin(
            (anchor + travel) * configuration.detailBandFrequency
                + configuration.detailBandPhase
        ) - sin(
            anchor * configuration.detailBandFrequency
                + configuration.detailBandPhase
        )
        return anchor
            + travel
            + slowBand * configuration.slowBandStrength
            + detailBand * configuration.detailBandStrength
    }

    static func motionOffset(
        phase: CGFloat,
        lightFlow: Double,
        pauseThreshold: Double,
        width: CGFloat,
        height: CGFloat,
        configuration: BarSceneConfiguration.Motion
    ) -> CGPoint {
        let flowStrength = activeFlowStrength(lightFlow, pauseThreshold: pauseThreshold)
        guard flowStrength > 0 else { return .zero }
        let amplitude = configuration.amplitudeBase
            + flowStrength * configuration.amplitudeSpan
        let positionX = sin(phase * 0.58 + configuration.phaseOffset)
            * configuration.horizontalPrimary
            + sin(phase * 1.21 + 1.4) * configuration.horizontalSecondary
        let positionY = cos(phase * 0.46 + configuration.phaseOffset)
            * configuration.verticalPrimary
            + sin(phase * 0.91 + 2.2) * configuration.verticalSecondary
        return CGPoint(x: width * amplitude * positionX, y: height * amplitude * positionY)
    }

    private static func activeFlowStrength(
        _ lightFlow: Double,
        pauseThreshold: Double
    ) -> CGFloat {
        guard lightFlow >= pauseThreshold else { return 0 }
        let clampedFlow = min(max(lightFlow, 0), 1)
        let smoothFlow = clampedFlow * clampedFlow * (3 - 2 * clampedFlow)
        return CGFloat(0.28 + smoothFlow * 0.72)
    }
}
