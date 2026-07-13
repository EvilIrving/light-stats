//
//  ThemeBackgroundView.swift
//  Light Stats
//

import SwiftUI

/// Renders native glass or one of the two curated, fully static tonal backgrounds.
struct ThemeBackgroundView: View {
    let tokens: ThemeTokens
    var cornerRadius: CGFloat = 12
    var configuresWindow: Bool = false
    var fallbackMaterial: NSVisualEffectView.Material = .sidebar

    var body: some View {
        Group {
            if tokens.usesStaticArtwork {
                StaticTonalBackground(tokens: tokens)
            } else if tokens.usesGlass {
                GlassBackgroundView(
                    cornerRadius: cornerRadius,
                    fallbackMaterial: fallbackMaterial,
                    configuresWindow: configuresWindow
                )
            } else {
                tokens.canvas
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct StaticTonalBackground: View {
    let tokens: ThemeTokens

    @ViewBuilder
    var body: some View {
        switch tokens.theme {
        case .film:
            SunGoldTonalBackground(tokens: tokens)
        case .noir:
            InkNightTonalBackground(tokens: tokens)
        case .bento, .glass:
            tokens.canvas
        }
    }
}

private struct SunGoldTonalBackground: View {
    let tokens: ThemeTokens

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = max(size.width, size.height)

            ZStack {
                tokens.canvas

                RadialGradient(
                    colors: [
                        tokens.artworkGlow,
                        tokens.artworkGlow.opacity(0.62),
                        Color.clear
                    ],
                    center: UnitPoint(x: -0.04, y: -0.02),
                    startRadius: 0,
                    endRadius: scale * 0.72
                )

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                tokens.artworkShadow.opacity(0.62),
                                tokens.artworkMidtone.opacity(0.40),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: min(size.width, size.height) * 0.52
                        )
                    )
                    .frame(width: size.width * 1.55, height: size.height * 0.43)
                    .rotationEffect(.degrees(-23))
                    .offset(x: size.width * 0.10, y: -size.height * 0.16)
                    .blur(radius: scale * 0.055)

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                tokens.artworkMidtone.opacity(0.34),
                                tokens.artworkMidtone.opacity(0.17),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: min(size.width, size.height) * 0.46
                        )
                    )
                    .frame(width: size.width * 1.10, height: size.height * 0.48)
                    .rotationEffect(.degrees(-14))
                    .offset(x: -size.width * 0.36, y: size.height * 0.18)
                    .blur(radius: scale * 0.10)

                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.49, blue: 0.35).opacity(0.94),
                        Color(red: 0.97, green: 0.40, blue: 0.31).opacity(0.54),
                        Color.clear
                    ],
                    center: UnitPoint(x: 1.04, y: 0.96),
                    startRadius: 0,
                    endRadius: scale * 0.68
                )

                LinearGradient(
                    colors: [
                        tokens.artworkGlow.opacity(0.08),
                        tokens.artworkGlow.opacity(0.04),
                        tokens.artworkGlow.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                GrainTextureView(opacity: tokens.textureOpacity, warmth: 0.44)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

private struct InkNightTonalBackground: View {
    let tokens: ThemeTokens

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = max(size.width, size.height)

            ZStack {
                tokens.canvas

                LinearGradient(
                    colors: [
                        tokens.artworkShadow,
                        tokens.canvas,
                        tokens.artworkShadow
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RoundedRectangle(cornerRadius: scale * 0.20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tokens.artworkGlow.opacity(0.30),
                                tokens.artworkMidtone.opacity(0.19),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size.width * 0.62, height: size.height * 1.08)
                    .rotationEffect(.degrees(8))
                    .offset(x: -size.width * 0.25, y: -size.height * 0.08)
                    .blur(radius: scale * 0.075)

                Ellipse()
                    .fill(tokens.artworkGlow.opacity(0.11))
                    .frame(width: size.width * 0.78, height: size.height * 0.24)
                    .rotationEffect(.degrees(-7))
                    .offset(x: -size.width * 0.23, y: -size.height * 0.39)
                    .blur(radius: scale * 0.065)

                RoundedRectangle(cornerRadius: scale * 0.12, style: .continuous)
                    .fill(tokens.artworkShadow.opacity(0.66))
                    .frame(width: size.width * 0.34, height: size.height * 1.18)
                    .rotationEffect(.degrees(5))
                    .offset(x: size.width * 0.13, y: size.height * 0.03)
                    .blur(radius: scale * 0.045)

                RadialGradient(
                    colors: [
                        tokens.artworkMidtone.opacity(0.08),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.17, y: 0.43),
                    startRadius: 0,
                    endRadius: scale * 0.46
                )

                GrainTextureView(opacity: tokens.textureOpacity, warmth: 0)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .allowsHitTesting(false)
    }
}
