//
//  NoirMeshRenderer.swift
//  Light Stats
//
//  Cool vertical shaft light field. Visual parameters are unchanged from
//  the previous inlined NoirLightField; this type no longer knows AppTheme.
//

import SwiftUI

struct NoirMeshRenderer: View {
    let configuration: BackgroundConfiguration
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
                    configuration.meshBlobHighlight.opacity(0.45),
                    configuration.meshBlobSecondary.opacity(0.35),
                    configuration.meshBlobPrimary.opacity(0.5),
                    configuration.meshBase
                ],
                startPoint: UnitPoint(x: 0.5 + sin(phase) * 0.04, y: 0.0),
                endPoint: UnitPoint(x: 0.5, y: 1.0)
            )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            configuration.meshBlobHighlight.opacity(0.85),
                            configuration.meshBlobSecondary.opacity(0.55),
                            configuration.meshBlobPrimary.opacity(0.2),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.3),
                        startRadius: 0,
                        endRadius: scale * 0.95
                    )
                )
                .frame(width: width * 1.05, height: height * 1.7)
                .blur(radius: scale * 0.16)
                .offset(x: width * 0.14 + driftX + shiftX, y: -height * 0.1 + driftY + shiftY)
                .blendMode(.screen)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            configuration.meshBlobSecondary.opacity(0.32),
                            configuration.meshBlobPrimary.opacity(0.18),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: scale * 0.7
                    )
                )
                .frame(width: width * 1.05, height: height * 0.8)
                .blur(radius: scale * 0.2)
                .offset(x: -width * 0.26 + driftX2 + shiftX, y: height * 0.24 + driftY2 + shiftY)
                .blendMode(.plusLighter)
                .opacity(0.4)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            configuration.meshBlobHighlight.opacity(0.8),
                            configuration.meshBlobSecondary.opacity(0.55),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width * 0.48, height: height * 1.65)
                .blur(radius: scale * 0.1)
                .rotationEffect(.degrees(14 + Double(sin(phase)) * 5))
                .offset(x: width * 0.1 + driftX * 0.5 + shiftX, y: driftY * 0.35 + shiftY)
                .blendMode(.screen)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            configuration.meshBlobSecondary.opacity(0.28),
                            configuration.meshBlobHighlight.opacity(0.14),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width * 0.24, height: height * 1.2)
                .blur(radius: scale * 0.14)
                .rotationEffect(.degrees(-20 + Double(cos(phase * 0.9)) * 4))
                .offset(x: -width * 0.18 + driftX2 * 0.6 + shiftX, y: height * 0.06 + driftY2 * 0.3 + shiftY)
                .blendMode(.screen)
                .opacity(0.35)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            configuration.meshBlobHighlight.opacity(0.28),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.0),
                        startRadius: 0,
                        endRadius: scale * 0.6
                    )
                )
                .frame(width: width * 1.15, height: height * 0.5)
                .blur(radius: scale * 0.14)
                .offset(x: shiftX, y: -height * 0.3 + driftY * 0.2 + shiftY)
                .blendMode(.plusLighter)
                .opacity(0.45)

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
        }
    }
}
