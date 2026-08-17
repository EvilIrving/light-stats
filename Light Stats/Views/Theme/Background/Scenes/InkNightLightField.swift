//
//  InkNightLightField.swift
//  Light Stats
//

import SwiftUI

struct InkNightLightField: View {
    let configuration: InkNightSceneConfiguration.LightField
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let phase: CGFloat
    let shiftX: CGFloat
    let shiftY: CGFloat

    var body: some View {
        let driftX = sin(phase * 0.9) * width * 0.04
        let driftY = cos(phase) * height * 0.065
        let driftX2 = cos(phase * 1.1 + 0.5) * width * 0.05
        let driftY2 = sin(phase * 0.7 + 1.0) * height * 0.05

        return ZStack {
            configuration.meshBase

            LinearGradient(
                colors: [
                    configuration.highlight.opacity(0.45),
                    configuration.secondary.opacity(0.35),
                    configuration.primary.opacity(0.5),
                    configuration.meshBase
                ],
                startPoint: UnitPoint(x: 0.5 + sin(phase) * 0.04, y: 0.0),
                endPoint: UnitPoint(x: 0.5, y: 1.0)
            )

            if configuration.primaryShaft.isEnabled {
                let layer = configuration.primaryShaft
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                configuration.highlight.opacity(0.85),
                                configuration.secondary.opacity(0.55),
                                configuration.primary.opacity(0.2),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.5, y: 0.3),
                            startRadius: 0,
                            endRadius: scale * 0.95
                        )
                    )
                    .frame(width: width * 1.05, height: height * 1.7)
                    .blur(radius: scale * layer.blurRadiusScale)
                    .offset(
                        x: width * 0.14 + (driftX + shiftX) * layer.motionScale,
                        y: -height * 0.1 + (driftY + shiftY) * layer.motionScale
                    )
                    .blendMode(.screen)
                    .opacity(layer.opacity)
            }

            if configuration.ambientGlow.isEnabled {
                let layer = configuration.ambientGlow
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                configuration.secondary.opacity(0.32),
                                configuration.primary.opacity(0.18),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: scale * 0.7
                        )
                    )
                    .frame(width: width * 1.05, height: height * 0.8)
                    .blur(radius: scale * layer.blurRadiusScale)
                    .offset(
                        x: -width * 0.26 + (driftX2 + shiftX) * layer.motionScale,
                        y: height * 0.24 + (driftY2 + shiftY) * layer.motionScale
                    )
                    .blendMode(.plusLighter)
                    .opacity(layer.opacity)
            }

            if configuration.primaryBeam.isEnabled {
                let layer = configuration.primaryBeam
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                configuration.highlight.opacity(0.8),
                                configuration.secondary.opacity(0.55),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width * 0.48, height: height * 1.65)
                    .blur(radius: scale * layer.blurRadiusScale)
                    .rotationEffect(.degrees(
                        14 + Double(sin(phase)) * 5 * Double(layer.motionScale)
                    ))
                    .offset(
                        x: width * 0.1
                            + (driftX * 0.5 + shiftX) * layer.motionScale,
                        y: (driftY * 0.35 + shiftY) * layer.motionScale
                    )
                    .blendMode(.screen)
                    .opacity(layer.opacity)
            }

            if configuration.secondaryBeam.isEnabled {
                let layer = configuration.secondaryBeam
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                configuration.secondary.opacity(0.28),
                                configuration.highlight.opacity(0.14),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width * 0.24, height: height * 1.2)
                    .blur(radius: scale * layer.blurRadiusScale)
                    .rotationEffect(.degrees(
                        -20 + Double(cos(phase * 0.9)) * 4 * Double(layer.motionScale)
                    ))
                    .offset(
                        x: -width * 0.18
                            + (driftX2 * 0.6 + shiftX) * layer.motionScale,
                        y: height * 0.06
                            + (driftY2 * 0.3 + shiftY) * layer.motionScale
                    )
                    .blendMode(.screen)
                    .opacity(layer.opacity)
            }

            if configuration.topGlow.isEnabled {
                let layer = configuration.topGlow
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                configuration.highlight.opacity(0.28),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.5, y: 0.0),
                            startRadius: 0,
                            endRadius: scale * 0.6
                        )
                    )
                    .frame(width: width * 1.15, height: height * 0.5)
                    .blur(radius: scale * layer.blurRadiusScale)
                    .offset(
                        x: shiftX * layer.motionScale,
                        y: -height * 0.3
                            + (driftY * 0.2 + shiftY) * layer.motionScale
                    )
                    .blendMode(.plusLighter)
                    .opacity(layer.opacity)
            }

            if configuration.lowerShade.isEnabled {
                let layer = configuration.lowerShade
                LinearGradient(
                    colors: [
                        Color.clear,
                        configuration.meshBase.opacity(0.35),
                        configuration.meshBase.opacity(0.75)
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0.35),
                    endPoint: .bottom
                )
                .blendMode(.multiply)
                .opacity(layer.opacity)
            }
        }
    }
}
