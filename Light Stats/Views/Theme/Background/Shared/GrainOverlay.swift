//
//  GrainOverlay.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// Full-bleed film grain. Keep outside light-field drawing groups so the grain stays crisp.
struct GrainOverlay: View {
    let configuration: GrainOverlayConfiguration
    let isEnabled: Bool

    private var effectiveOpacity: Double {
        isEnabled ? configuration.opacity : 0
    }

    var body: some View {
        if effectiveOpacity <= 0.001 {
            EmptyView()
        } else {
            ZStack {
                texture(GrainTextureCache.fine, opacity: effectiveOpacity)
                    .blendMode(.softLight)

                texture(
                    GrainTextureCache.body,
                    opacity: effectiveOpacity * configuration.bodyOpacityRatio
                )
                .blendMode(.overlay)

                if configuration.warmth > 0.001 {
                    configuration.warmTint
                        .opacity(
                            configuration.warmth
                                * effectiveOpacity
                                * configuration.warmthOpacityRatio
                        )
                        .blendMode(.softLight)
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func texture(_ image: NSImage, opacity: Double) -> some View {
        let scale = max(configuration.scale, 0.05)
        if abs(scale - 1) < 0.001 {
            tiledImage(image, opacity: opacity)
        } else {
            GeometryReader { geometry in
                tiledImage(image, opacity: opacity)
                    .frame(
                        width: geometry.size.width / scale,
                        height: geometry.size.height / scale
                    )
                    .scaleEffect(scale, anchor: .topLeading)
            }
            .clipped()
        }
    }

    private func tiledImage(_ image: NSImage, opacity: Double) -> some View {
        Image(nsImage: image)
            .resizable(resizingMode: .tile)
            .interpolation(.none)
            .opacity(opacity)
    }
}
