//
//  GrainTextureView.swift
//  Light Stats
//

import AppKit
import CoreImage
import SwiftUI

/// Full-bleed cached microtexture generated once by Core Image.
struct GrainTextureView: View {
    /// Four source pixels per layout point keep Retina captures from exposing noise cells.
    static let samplingScale: CGFloat = 4

    let opacity: Double
    let warmth: Double

    var body: some View {
        if opacity > 0.001 {
            ZStack {
                Image(nsImage: GrainTextureCache.texture)
                    .resizable(resizingMode: .tile)
                    .interpolation(.high)
                    .opacity(opacity)
                    .blendMode(.softLight)

                if warmth > 0.001 {
                    Color(red: 0.90, green: 0.45, blue: 0.25)
                        .opacity(warmth * opacity * 0.08)
                        .blendMode(.softLight)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private enum GrainTextureCache {
    static let texture = makeNoise(pointDimension: 256, contrast: 1.22, blurRadius: 0.55)

    private static func makeNoise(
        pointDimension: Int,
        contrast: Double,
        blurRadius: Double
    ) -> NSImage {
        let pixelDimension = CGFloat(pointDimension) * GrainTextureView.samplingScale
        let extent = CGRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension)
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else {
            return NSImage(size: CGSize(width: pointDimension, height: pointDimension))
        }
        let monochrome = random
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 0,
                    kCIInputContrastKey: contrast,
                    kCIInputBrightnessKey: 0
                ]
            )
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: blurRadius]
            )
            .cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let image = context.createCGImage(monochrome, from: extent) else {
            return NSImage(size: CGSize(width: pointDimension, height: pointDimension))
        }
        let pointSize = CGSize(width: pointDimension, height: pointDimension)
        let texture = NSImage(cgImage: image, size: pointSize)
        texture.resizingMode = .tile
        return texture
    }
}
