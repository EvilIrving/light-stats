//
//  SunGoldLightField.swift
//  Light Stats
//

import SwiftUI

struct SunGoldLightField: View {
    let configuration: SunGoldSceneConfiguration.LightField
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let phase: CGFloat
    let shiftX: CGFloat
    let shiftY: CGFloat

    var body: some View {
        let driftX = cos(phase) * width * 0.12
        let driftY = sin(phase * 0.75) * height * 0.08
        let driftX2 = cos(phase * 0.95 + 1.1) * width * 0.09
        let driftY2 = sin(phase * 1.05 + 0.5) * height * 0.075
        let phaseX = cos(phase) * 0.08
        let ribbonTwist = Double(sin(phase)) * 9
        let ribbonTwist2 = Double(cos(phase * 0.85)) * 7
        let compositionTilt = Double(shiftX / max(width, 1)) * 12

        return ZStack {
            configuration.meshBase

            LinearGradient(
                colors: [
                    configuration.highlight.opacity(0.75),
                    configuration.secondary.opacity(0.60),
                    configuration.primary.opacity(0.70),
                    configuration.meshBase
                ],
                startPoint: UnitPoint(x: 0.0 + phaseX, y: 0.0),
                endPoint: UnitPoint(x: 1.0, y: 1.0)
            )

            ZStack {
                if configuration.primaryGlow.isEnabled {
                    let layer = configuration.primaryGlow
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    configuration.secondary.opacity(0.98),
                                    configuration.secondary.opacity(0.60),
                                    configuration.primary.opacity(0.30),
                                    Color.clear
                                ],
                                center: UnitPoint(x: 0.65, y: 0.6),
                                startRadius: 0,
                                endRadius: scale * 0.9
                            )
                        )
                        .frame(width: width * 1.7, height: height * 1.25)
                        .blur(radius: scale * layer.blurRadiusScale)
                        .offset(
                            x: width * 0.22 + (driftX + shiftX) * layer.motionScale,
                            y: height * 0.2 + (driftY + shiftY) * layer.motionScale
                        )
                        .blendMode(.plusLighter)
                        .opacity(layer.opacity)
                }

                if configuration.ambientGlow.isEnabled {
                    let layer = configuration.ambientGlow
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    configuration.primary.opacity(0.60),
                                    configuration.primary.opacity(0.25),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: scale * 0.75
                            )
                        )
                        .frame(width: width * 1.2, height: height * 0.9)
                        .blur(radius: scale * layer.blurRadiusScale)
                        .offset(
                            x: -width * 0.22
                                + (driftX * 0.45 + shiftX) * layer.motionScale,
                            y: -height * 0.1
                                + (-driftY * 0.35 + shiftY) * layer.motionScale
                        )
                        .blendMode(.normal)
                        .opacity(layer.opacity)
                }

                if configuration.primaryRibbon.isEnabled {
                    let layer = configuration.primaryRibbon
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    configuration.highlight.opacity(0.90),
                                    configuration.secondary.opacity(0.80),
                                    configuration.highlight.opacity(0.50),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * 1.85, height: height * 0.40)
                        .blur(radius: scale * layer.blurRadiusScale)
                        .rotationEffect(.degrees(
                            -26 + (ribbonTwist + compositionTilt) * Double(layer.motionScale)
                        ))
                        .offset(
                            x: (driftX * 0.8 + shiftX) * layer.motionScale,
                            y: height * 0.04
                                + (driftY * 0.7 + shiftY) * layer.motionScale
                        )
                        .blendMode(.screen)
                        .opacity(layer.opacity)
                }

                if configuration.secondaryRibbon.isEnabled {
                    let layer = configuration.secondaryRibbon
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    configuration.secondary.opacity(0.35),
                                    configuration.highlight.opacity(0.20),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * 1.35, height: height * 0.18)
                        .blur(radius: scale * layer.blurRadiusScale)
                        .rotationEffect(.degrees(
                            -16
                                + (ribbonTwist2 + compositionTilt * 0.5)
                                * Double(layer.motionScale)
                        ))
                        .offset(
                            x: -width * 0.06 + (driftX2 + shiftX) * layer.motionScale,
                            y: -height * 0.14 + (driftY2 + shiftY) * layer.motionScale
                        )
                        .blendMode(.screen)
                        .opacity(layer.opacity)
                }

                if configuration.highlightGlow.isEnabled {
                    let layer = configuration.highlightGlow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    configuration.highlight.opacity(0.40),
                                    configuration.highlight.opacity(0.10),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: scale * 0.55
                            )
                        )
                        .frame(width: width * 0.9, height: height * 0.7)
                        .blur(radius: scale * layer.blurRadiusScale)
                        .offset(
                            x: -width * 0.32
                                + (driftX2 * 0.4 + shiftX) * layer.motionScale,
                            y: -height * 0.32
                                + (driftY2 * 0.3 + shiftY) * layer.motionScale
                        )
                        .blendMode(.plusLighter)
                        .opacity(layer.opacity)
                }
            }
        }
    }
}
