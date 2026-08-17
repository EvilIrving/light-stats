//
//  GrainTextureCache.swift
//  Light Stats
//

import AppKit

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
            state = state &* 1_664_525 &+ 1_013_904_223
            let unit = Double((state >> 16) & 0xFFFF) / 65_535.0
            state = state &* 1_664_525 &+ 1_013_904_223
            let unit2 = Double((state >> 16) & 0xFFFF) / 65_535.0
            let mixed = unit * 0.72 + unit2 * 0.28
            let delta = Int(((mixed - 0.5) * 2.0) * Double(amp))
            pixels[index] = UInt8(min(255, max(0, mid + delta)))
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
