//
//  FilmMeshRenderer.swift
//  Light Stats
//
//  Warm diagonal S-curve light field. Visual parameters are unchanged from
//  the previous inlined FilmLightField; this type no longer knows AppTheme.
//

import SwiftUI

struct FilmMeshRenderer: View {
    let configuration: BackgroundConfiguration
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let phase: CGFloat
    var shiftX: CGFloat = 0
    var shiftY: CGFloat = 0

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
                    configuration.meshBlobHighlight.opacity(0.75),
                    configuration.meshBlobSecondary.opacity(0.60),
                    configuration.meshBlobPrimary.opacity(0.70),
                    configuration.meshBase
                ],
                startPoint: UnitPoint(x: 0.0 + phaseX, y: 0.0),
                endPoint: UnitPoint(x: 1.0, y: 1.0)
            )

            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                configuration.meshBlobSecondary.opacity(0.98),
                                configuration.meshBlobSecondary.opacity(0.60),
                                configuration.meshBlobPrimary.opacity(0.30),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.65, y: 0.6),
                            startRadius: 0,
                            endRadius: scale * 0.9
                        )
                    )
                    .frame(width: width * 1.7, height: height * 1.25)
                    .blur(radius: scale * 0.18)
                    .offset(x: width * 0.22 + driftX, y: height * 0.2 + driftY)
                    .blendMode(.plusLighter)

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                configuration.meshBlobPrimary.opacity(0.60),
                                configuration.meshBlobPrimary.opacity(0.25),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: scale * 0.75
                        )
                    )
                    .frame(width: width * 1.2, height: height * 0.9)
                    .blur(radius: scale * 0.18)
                    .offset(x: -width * 0.22 + driftX * 0.45, y: -height * 0.1 - driftY * 0.35)
                    .blendMode(.normal)
                    .opacity(0.6)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                configuration.meshBlobHighlight.opacity(0.90),
                                configuration.meshBlobSecondary.opacity(0.80),
                                configuration.meshBlobHighlight.opacity(0.50),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 1.85, height: height * 0.40)
                    .blur(radius: scale * 0.08)
                    .rotationEffect(.degrees(-26 + ribbonTwist + compositionTilt))
                    .offset(x: driftX * 0.8, y: height * 0.04 + driftY * 0.7)
                    .blendMode(.screen)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                configuration.meshBlobSecondary.opacity(0.35),
                                configuration.meshBlobHighlight.opacity(0.20),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 1.35, height: height * 0.18)
                    .blur(radius: scale * 0.12)
                    .rotationEffect(.degrees(-16 + ribbonTwist2 + compositionTilt * 0.5))
                    .offset(x: -width * 0.06 + driftX2, y: -height * 0.14 + driftY2)
                    .blendMode(.screen)
                    .opacity(0.5)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                configuration.meshBlobHighlight.opacity(0.40),
                                configuration.meshBlobHighlight.opacity(0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: scale * 0.55
                        )
                    )
                    .frame(width: width * 0.9, height: height * 0.7)
                    .blur(radius: scale * 0.14)
                    .offset(x: -width * 0.32 + driftX2 * 0.4, y: -height * 0.32 + driftY2 * 0.3)
                    .blendMode(.plusLighter)
                    .opacity(0.55)
            }
            .offset(x: shiftX, y: shiftY)
        }
    }
}
