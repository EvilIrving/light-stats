//
//  PresentationCursorAtlas.swift
//  Light Stats
//
//  Sprite-atlas geometry and decoding for the presentation cursor: pure grid math
//  plus one bundle decode, so the frame layout is testable without a window.
//

import AppKit
import CoreGraphics
import Foundation

/// Atlas contract from the asset pack: 6 columns × 8 rows of 128px cells, read
/// row-major, 50 ms per frame (2.4 s per loop). The pack documents it in
/// `动画参数.json`; `Resources/Cursors/ATTRIBUTION.txt` repeats it next to the art.
nonisolated enum PresentationCursorAtlas {
    static let columns = 6
    static let rows = 8
    static let cellPixels = 128
    static let secondsPerFrame: TimeInterval = 0.05

    static var frameCount: Int { columns * rows }

    static var loopDuration: TimeInterval { Double(frameCount) * secondsPerFrame }

    /// Crop used for the settings thumbnails: the arrow tip is near the cell's top-left
    /// corner and the body opens to the right, so every colourway's artwork sits inside
    /// `x 18…109, y 3…124`. Cropping to this shared box keeps the thumbnails the same
    /// size and centred instead of letting each cell's empty margin set the framing.
    static let previewRect = CGRect(x: 16, y: 0, width: 96, height: 128)

    /// Frame rectangles in atlas space — origin top-left, `y` growing downward, the
    /// same space `CGImage.cropping(to:)` uses. Index order is the playback order.
    static func frameRects(
        columns: Int = PresentationCursorAtlas.columns,
        rows: Int = PresentationCursorAtlas.rows,
        cellPixels: Int = PresentationCursorAtlas.cellPixels
    ) -> [CGRect] {
        guard columns > 0, rows > 0, cellPixels > 0 else { return [] }
        let side = CGFloat(cellPixels)
        return (0..<(columns * rows)).map { index in
            CGRect(
                x: CGFloat(index % columns) * side,
                y: CGFloat(index / columns) * side,
                width: side,
                height: side
            )
        }
    }

    /// Discrete key times for a Core Animation sequence over `contents`: one entry per
    /// frame, the last one below 1 so the loop wraps instead of holding the final frame
    /// twice.
    static func keyTimes(frameCount: Int = PresentationCursorAtlas.frameCount) -> [NSNumber] {
        guard frameCount > 0 else { return [] }
        return (0..<frameCount).map { NSNumber(value: Double($0) / Double(frameCount)) }
    }

    /// Slice `atlas` into its frames in playback order. Returns fewer frames than the
    /// contract requires when the atlas is not the documented size, because
    /// `cropping(to:)` refuses a rectangle that leaves the image.
    static func slices(
        from atlas: CGImage,
        columns: Int = PresentationCursorAtlas.columns,
        rows: Int = PresentationCursorAtlas.rows,
        cellPixels: Int = PresentationCursorAtlas.cellPixels
    ) -> [CGImage] {
        frameRects(columns: columns, rows: rows, cellPixels: cellPixels)
            .compactMap { atlas.cropping(to: $0) }
    }

    /// Decode the bundled atlas for `style`. Nil when the resource is missing or does
    /// not match the grid, so the caller can leave the real cursor alone.
    static func loadFrames(for style: PresentationCursorStyle) -> [CGImage]? {
        guard let url = resourceURL(named: style.atlasResourceName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let frames = slices(from: atlas)
        return frames.count == frameCount ? frames : nil
    }

    /// One frame as a still image for the settings picker, cropped to `previewRect` and
    /// sized to points at half the artwork's pixels so a 2× display stays sharp.
    static func previewImage(for style: PresentationCursorStyle, frameIndex: Int = 0) -> NSImage? {
        let rects = frameRects()
        guard rects.indices.contains(frameIndex),
              let url = resourceURL(named: style.atlasResourceName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let cell = rects[frameIndex]
        let crop = previewRect.offsetBy(dx: cell.minX, dy: cell.minY)
        guard let artwork = atlas.cropping(to: crop) else { return nil }
        return NSImage(
            cgImage: artwork,
            size: NSSize(width: crop.width / 2, height: crop.height / 2)
        )
    }

    /// Synchronized folder groups copy resources flat into the bundle, so the
    /// `Cursors` subdirectory is only present if the project ever preserves it.
    private static func resourceURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Cursors")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
    }
}
