//
//  BarLightField.swift
//  Light Stats
//

import SwiftUI

struct BarLightField: View {
    let configuration: BarSceneConfiguration.LightField
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let phase: CGFloat
    let shiftX: CGFloat
    let shiftY: CGFloat

    private var warmDrift: CGPoint {
        CGPoint(
            x: sin(phase * 0.82) * width * 0.055,
            y: cos(phase * 0.68) * height * 0.05
        )
    }

    private var coolDrift: CGPoint {
        CGPoint(
            x: cos(phase * 0.76 + 1.1) * width * 0.06,
            y: sin(phase * 0.88 + 0.4) * height * 0.055
        )
    }

    var body: some View {
        ZStack {
            configuration.meshBase
            baseColorWash
            warmGlow
            coolGlow
            warmTube
            coolTube
            lampGlow
            counterReflection
            lowerShade
        }
    }

    private var baseColorWash: some View {
        LinearGradient(
            colors: [
                configuration.warm.opacity(0.36),
                configuration.meshBase,
                configuration.cool.opacity(0.22),
                configuration.meshBase
            ],
            startPoint: UnitPoint(x: 0.0, y: 0.08),
            endPoint: UnitPoint(x: 1.0, y: 0.92)
        )
    }

    @ViewBuilder
    private var warmGlow: some View {
        if configuration.warmGlow.isEnabled {
            let layer = configuration.warmGlow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            configuration.warm.opacity(0.84),
                            configuration.warm.opacity(0.32),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.38, y: 0.45),
                        startRadius: 0,
                        endRadius: scale * 0.9
                    )
                )
                .frame(width: width * 1.15, height: height * 1.25)
                .blur(radius: scale * layer.blurRadiusScale)
                .offset(
                    x: -width * 0.30 + (warmDrift.x + shiftX) * layer.motionScale,
                    y: height * 0.03 + (warmDrift.y + shiftY) * layer.motionScale
                )
                .blendMode(.plusLighter)
                .opacity(layer.opacity)
        }
    }

    @ViewBuilder
    private var coolGlow: some View {
        if configuration.coolGlow.isEnabled {
            let layer = configuration.coolGlow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            configuration.cool.opacity(0.74),
                            configuration.cool.opacity(0.26),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.62, y: 0.38),
                        startRadius: 0,
                        endRadius: scale * 0.88
                    )
                )
                .frame(width: width * 1.10, height: height * 1.15)
                .blur(radius: scale * layer.blurRadiusScale)
                .offset(
                    x: width * 0.31 + (coolDrift.x + shiftX) * layer.motionScale,
                    y: -height * 0.08 + (coolDrift.y + shiftY) * layer.motionScale
                )
                .blendMode(.plusLighter)
                .opacity(layer.opacity)
        }
    }

    @ViewBuilder
    private var warmTube: some View {
        if configuration.warmTube.isEnabled {
            let layer = configuration.warmTube
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            configuration.warm.opacity(0.94),
                            Color.white.opacity(0.82),
                            configuration.warm.opacity(0.90),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width * 0.13, height: height * 1.35)
                .blur(radius: scale * layer.blurRadiusScale)
                .rotationEffect(.degrees(-17 + Double(sin(phase * 0.73)) * 4))
                .offset(
                    x: -width * 0.30 + (warmDrift.x + shiftX) * layer.motionScale,
                    y: -height * 0.02 + (warmDrift.y + shiftY) * layer.motionScale
                )
                .blendMode(.screen)
                .opacity(layer.opacity)
        }
    }

    @ViewBuilder
    private var coolTube: some View {
        if configuration.coolTube.isEnabled {
            let layer = configuration.coolTube
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            configuration.cool.opacity(0.90),
                            Color.white.opacity(0.76),
                            configuration.cool.opacity(0.88),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width * 0.11, height: height * 1.30)
                .blur(radius: scale * layer.blurRadiusScale)
                .rotationEffect(.degrees(16 + Double(cos(phase * 0.81)) * 4))
                .offset(
                    x: width * 0.33 + (coolDrift.x + shiftX) * layer.motionScale,
                    y: height * 0.02 + (coolDrift.y + shiftY) * layer.motionScale
                )
                .blendMode(.screen)
                .opacity(layer.opacity)
        }
    }

    @ViewBuilder
    private var lampGlow: some View {
        if configuration.lampGlow.isEnabled {
            let layer = configuration.lampGlow
            HStack(spacing: width * 0.06) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    configuration.amber.opacity(0.82),
                                    configuration.warm.opacity(0.18),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: scale * 0.10
                            )
                        )
                        .frame(width: scale * 0.13, height: scale * 0.13)
                        .offset(y: index == 1 ? scale * 0.025 : 0)
                }
            }
            .blur(radius: scale * layer.blurRadiusScale)
            .offset(
                x: width * 0.03 + shiftX * layer.motionScale,
                y: -height * 0.39 + shiftY * layer.motionScale
            )
            .blendMode(.plusLighter)
            .opacity(layer.opacity)
        }
    }

    @ViewBuilder
    private var counterReflection: some View {
        if configuration.counterReflection.isEnabled {
            let layer = configuration.counterReflection
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            configuration.warm.opacity(0.66),
                            configuration.amber.opacity(0.34),
                            configuration.cool.opacity(0.58),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * 1.18, height: height * 0.12)
                .blur(radius: scale * layer.blurRadiusScale)
                .rotationEffect(.degrees(-3 + Double(sin(phase * 0.55)) * 2))
                .offset(
                    x: shiftX * layer.motionScale,
                    y: height * 0.37 + shiftY * layer.motionScale
                )
                .blendMode(.screen)
                .opacity(layer.opacity)
        }
    }

    private var lowerShade: some View {
        LinearGradient(
            colors: [
                Color.clear,
                configuration.meshBase.opacity(0.25),
                Color.black.opacity(0.58)
            ],
            startPoint: UnitPoint(x: 0.5, y: 0.48),
            endPoint: .bottom
        )
        .blendMode(.multiply)
    }
}
