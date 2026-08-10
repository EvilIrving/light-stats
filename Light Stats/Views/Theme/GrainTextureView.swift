//
//  GrainTextureView.swift
//  Light Stats
//
//  Multi-scale film grain (xAI / Grok mood-image style). Generated once per
//  process; fine high-frequency layer + softer body layer, soft-light blend.
//

import AppKit
import SwiftUI

/// Full-bleed film grain. Pair with mesh backgrounds; keep *outside* any
/// `.drawingGroup()` that blurs light so the grain stays crisp.
///
/// Film and noir **must** share `GrainTextureCache` + the same opacity path so grit
/// fineness matches; only `warmth` may tint film toward the brown plate.
struct GrainTextureView: View {
    /// Overall strength. Mesh themes use ~0.32 soft-light.
    var opacity: Double
    /// Optional warm tint for Sun Gold / 晒金 (0 = neutral mono grit for Ink Night).
    var warmth: Double = 0

    var body: some View {
        if opacity <= 0.001 {
            EmptyView()
        } else {
            ZStack {
                // High-frequency grit — shared tile for every mesh theme.
                Image(nsImage: GrainTextureCache.fine)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
                    .opacity(opacity)
                    .blendMode(.softLight)

                // Body layer — same ratio for film and noir.
                Image(nsImage: GrainTextureCache.body)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
                    .opacity(opacity * 0.55)
                    .blendMode(.overlay)

                if warmth > 0.001 {
                    // Color only — does not change grain frequency or amplitude.
                    Color(red: 0.92, green: 0.62, blue: 0.42)
                        .opacity(warmth * opacity * 0.14)
                        .blendMode(.softLight)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Deterministic multi-scale film noise. One cache for all mesh themes.
enum GrainTextureCache {
    static let fine: NSImage = makeNoise(dimension: 256, seed: 0xC0FF_EE42, amplitude: 52)
    static let body: NSImage = makeNoise(dimension: 128, seed: 0xF11A_B0DE, amplitude: 38)

    private static func makeNoise(dimension: Int, seed: UInt32, amplitude: Int) -> NSImage {
        let bytesPerRow = dimension
        var pixels = [UInt8](repeating: 128, count: dimension * dimension)
        var state = seed == 0 ? 1 : seed
        let amp = max(8, min(amplitude, 90))
        let mid = 128

        for index in 0..<pixels.count {
            // Numerical Recipes LCG
            state = state &* 1_664_525 &+ 1_013_904_223
            let unit = Double((state >> 16) & 0xFFFF) / 65_535.0
            // Second sample — mild low-pass feel when mixed (less “TV static”).
            state = state &* 1_664_525 &+ 1_013_904_223
            let unit2 = Double((state >> 16) & 0xFFFF) / 65_535.0
            let mixed = unit * 0.72 + unit2 * 0.28
            let delta = Int(((mixed - 0.5) * 2.0) * Double(amp))
            let value = min(255, max(0, mid + delta))
            pixels[index] = UInt8(value)
        }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: dimension,
                height: dimension,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return NSImage(size: NSSize(width: dimension, height: dimension))
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: dimension, height: dimension))
        image.resizingMode = .tile
        return image
    }
}
