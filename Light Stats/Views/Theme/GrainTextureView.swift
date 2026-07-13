//
//  GrainTextureView.swift
//  Light Stats
//

import AppKit
import CoreImage
import SwiftUI

/// Full-bleed cached grain generated once by Core Image, never per pixel on the CPU.
struct GrainTextureView: View {
    let opacity: Double
    let warmth: Double

    var body: some View {
        if opacity > 0.001 {
            ZStack {
                Image(nsImage: GrainTextureCache.fine)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
                    .opacity(opacity)
                    .blendMode(.softLight)

                Image(nsImage: GrainTextureCache.body)
                    .resizable(resizingMode: .tile)
                    .interpolation(.medium)
                    .opacity(opacity * 0.48)
                    .blendMode(.overlay)

                if warmth > 0.001 {
                    Color(red: 0.90, green: 0.45, blue: 0.25)
                        .opacity(warmth * opacity * 0.12)
                        .blendMode(.softLight)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private enum GrainTextureCache {
    static let fine = makeNoise(dimension: 256)
    static let body = makeNoise(dimension: 128)

    private static func makeNoise(dimension: Int) -> NSImage {
        let extent = CGRect(x: 0, y: 0, width: dimension, height: dimension)
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else {
            return NSImage(size: extent.size)
        }
        let monochrome = random
            .cropped(to: extent)
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 0,
                    kCIInputContrastKey: 1.45,
                    kCIInputBrightnessKey: 0
                ]
            )
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let image = context.createCGImage(monochrome, from: extent) else {
            return NSImage(size: extent.size)
        }
        let texture = NSImage(cgImage: image, size: extent.size)
        texture.resizingMode = .tile
        return texture
    }
}
