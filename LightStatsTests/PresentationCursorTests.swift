//
//  PresentationCursorTests.swift
//  LightStatsTests
//
//  Pins the presentation-cursor atlas contract (grid, loop timing, hotspot
//  placement) that the overlay window and its Core Animation sequence depend on,
//  plus that the bundled artwork is the animation it claims to be.
//

import CoreGraphics
import XCTest
@testable import Light_Stats

final class PresentationCursorTests: XCTestCase {

    // MARK: - Atlas grid

    func testFrameRectsFollowRowMajorPlaybackOrder() {
        let rects = PresentationCursorAtlas.frameRects()

        XCTAssertEqual(rects.count, 48)
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 128, height: 128))
        XCTAssertEqual(rects[5], CGRect(x: 640, y: 0, width: 128, height: 128))
        XCTAssertEqual(rects[6], CGRect(x: 0, y: 128, width: 128, height: 128))
        XCTAssertEqual(rects[47], CGRect(x: 640, y: 896, width: 128, height: 128))
    }

    func testEveryFrameRectStaysInsideTheAtlas() {
        let atlas = CGRect(x: 0, y: 0, width: 768, height: 1024)

        for rect in PresentationCursorAtlas.frameRects() {
            XCTAssertTrue(atlas.contains(rect), "\(rect) leaves the 768x1024 atlas")
        }
    }

    func testKeyTimesSpreadAcrossTheLoopWithoutRepeatingTheLastFrame() {
        let times = PresentationCursorAtlas.keyTimes().map(\.doubleValue)

        XCTAssertEqual(times.count, 48)
        XCTAssertEqual(times.first, 0)
        XCTAssertEqual(times.last!, 47.0 / 48.0, accuracy: 1e-9)
        for index in 1..<times.count {
            XCTAssertGreaterThan(times[index], times[index - 1])
        }
    }

    func testLoopMatchesThePackTiming() {
        XCTAssertEqual(PresentationCursorAtlas.frameCount, 48)
        XCTAssertEqual(PresentationCursorAtlas.loopDuration, 2.4, accuracy: 1e-9)
    }

    /// The art is 128px per cell and is rendered at 64pt, which is what keeps the
    /// pointer pixel-exact on a 2× display instead of resampled.
    func testRenderedCellSizeIsTwoTimesTheArtwork() {
        XCTAssertEqual(
            PresentationCursorGeometry.renderSize * 2,
            CGFloat(PresentationCursorAtlas.cellPixels)
        )
    }

    func testSlicingAnAtlasSmallerThanTheGridYieldsNoFrames() throws {
        let image = try XCTUnwrap(makeImage(width: 128, height: 128))

        XCTAssertEqual(PresentationCursorAtlas.slices(from: image).count, 1)
    }

    // MARK: - Bundled artwork

    func testBundledAtlasSlicesIntoFortyEightFrames() throws {
        let frames = try XCTUnwrap(
            PresentationCursorAtlas.loadFrames(for: .holographicSilver),
            "PresentationCursorHolographicSilver.png is missing from the bundle"
        )

        XCTAssertEqual(frames.count, 48)
        XCTAssertEqual(frames[0].width, 128)
        XCTAssertEqual(frames[0].height, 128)
    }

    func testFirstFrameShowsAnArrowRatherThanAnEmptyCell() throws {
        let frames = try XCTUnwrap(PresentationCursorAtlas.loadFrames(for: .holographicSilver))

        XCTAssertGreaterThan(visiblePixelCount(frames[0]), 1_000)
    }

    /// The pack keeps the alpha channel identical in every frame and animates only the
    /// facet highlights, so this compares colour, not coverage (校验报告.json:
    /// 透明通道逐帧不变).
    func testFramesDifferSoTheCursorActuallyAnimates() throws {
        let frames = try XCTUnwrap(PresentationCursorAtlas.loadFrames(for: .holographicSilver))

        XCTAssertNotEqual(rgbaBytes(frames[0]), rgbaBytes(frames[24]))
    }

    // MARK: - Colourways

    func testEveryColourwayShipsItsOwnCompleteAtlas() throws {
        XCTAssertEqual(PresentationCursorStyle.allCases.count, 5)
        var resourceNames = Set<String>()
        for style in PresentationCursorStyle.allCases {
            let frames = try XCTUnwrap(
                PresentationCursorAtlas.loadFrames(for: style),
                "\(style.rawValue) atlas is missing from the bundle"
            )
            XCTAssertEqual(frames.count, 48, style.rawValue)
            XCTAssertTrue(
                resourceNames.insert(style.atlasResourceName).inserted,
                "\(style.rawValue) shares an atlas with another colourway"
            )
        }
    }

    /// A hotspot outside the cell would put the click point off the artwork — and the
    /// pointer would still look right, which is what makes this worth pinning.
    func testEveryColourwayKeepsItsArrowTipInsideTheCell() {
        let cell = CGFloat(PresentationCursorAtlas.cellPixels)
        for style in PresentationCursorStyle.allCases {
            let hotspot = style.cellHotspot
            XCTAssertGreaterThan(hotspot.x, 0, style.rawValue)
            XCTAssertGreaterThan(hotspot.y, 0, style.rawValue)
            XCTAssertLessThan(hotspot.x, cell, style.rawValue)
            XCTAssertLessThan(hotspot.y, cell, style.rawValue)
        }
    }

    /// The picker crops every colourway to one shared box so the thumbnails are framed
    /// alike; artwork reaching outside it would be cut off in the settings row.
    func testPreviewCropContainsEveryColourwaysArtwork() throws {
        for style in PresentationCursorStyle.allCases {
            let frames = try XCTUnwrap(PresentationCursorAtlas.loadFrames(for: style))
            for index in [0, 12, 24, 36, 47] {
                let bounds = try XCTUnwrap(
                    artworkBounds(frames[index]),
                    "\(style.rawValue) frame \(index) is empty"
                )
                XCTAssertTrue(
                    PresentationCursorAtlas.previewRect.contains(bounds),
                    "\(style.rawValue) frame \(index) artwork \(bounds) escapes the preview crop"
                )
            }
        }
    }

    func testPreviewImageIsTheCroppedStill() throws {
        let preview = try XCTUnwrap(PresentationCursorAtlas.previewImage(for: .obsidian))

        XCTAssertEqual(preview.size.width, PresentationCursorAtlas.previewRect.width / 2, accuracy: 0.001)
        XCTAssertEqual(preview.size.height, PresentationCursorAtlas.previewRect.height / 2, accuracy: 0.001)
        XCTAssertNil(PresentationCursorAtlas.previewImage(for: .obsidian, frameIndex: 999))
    }

    func testStyleWireFormatRoundTripsAndRejectsUnknownNames() {
        for style in PresentationCursorStyle.allCases {
            XCTAssertEqual(PresentationCursorStyle(rawValue: style.rawValue), style)
            XCTAssertEqual(style.titleKey, "settings.presentationCursor.style.\(style.rawValue)")
        }
        XCTAssertNil(PresentationCursorStyle(rawValue: "mystery"))
        XCTAssertEqual(PresentationCursorStyle.shippedDefault, .holographicSilver)
    }

    // MARK: - Background cursor grant

    func testBackgroundCursorGrantIsAttemptedOnceAndAFailureIsNotRetried() {
        var attempts = 0
        var control = BackgroundCursorControl(install: {
            attempts += 1
            return false
        })

        XCTAssertFalse(control.enableOnce())
        XCTAssertFalse(control.enableOnce())

        XCTAssertEqual(attempts, 1, "a failed grant must not be retried on every pointer start")
    }

    func testBackgroundCursorGrantRemembersSuccess() {
        var attempts = 0
        var control = BackgroundCursorControl(install: {
            attempts += 1
            return true
        })

        XCTAssertTrue(control.enableOnce())
        XCTAssertTrue(control.enableOnce())

        XCTAssertEqual(attempts, 1)
    }

    // MARK: - Placement

    func testHotspotScalesFromCellPixelsToRenderedPoints() {
        let hotspot = PresentationCursorGeometry.hotspot(
            cellHotspot: PresentationCursorStyle.holographicSilver.cellHotspot
        )

        XCTAssertEqual(hotspot.x, 12.0655, accuracy: 0.0005)
        XCTAssertEqual(hotspot.y, 2.0545, accuracy: 0.0005)
    }

    func testWindowOriginPutsTheArrowTipOnThePointer() {
        let hotspot = PresentationCursorGeometry.hotspot(
            cellHotspot: PresentationCursorStyle.holographicSilver.cellHotspot
        )
        let pointer = CGPoint(x: 812, y: 540)

        let origin = PresentationCursorGeometry.windowOrigin(pointer: pointer, hotspot: hotspot)
        // Image top-left in Cocoa coordinates, then the tip measured downward from it.
        let topLeft = CGPoint(
            x: origin.x,
            y: origin.y + PresentationCursorGeometry.renderSize
        )
        let tip = CGPoint(x: topLeft.x + hotspot.x, y: topLeft.y - hotspot.y)

        XCTAssertEqual(tip.x, pointer.x, accuracy: 1e-9)
        XCTAssertEqual(tip.y, pointer.y, accuracy: 1e-9)
    }

    /// A display arranged above the primary reports y greater than the primary's
    /// height; the origin must follow the pointer there instead of clamping.
    func testWindowOriginFollowsThePointerOntoADisplayAboveThePrimary() {
        let hotspot = PresentationCursorGeometry.hotspot(
            cellHotspot: PresentationCursorStyle.holographicSilver.cellHotspot
        )
        let pointer = CGPoint(x: 400, y: 1_600)

        let origin = PresentationCursorGeometry.windowOrigin(pointer: pointer, hotspot: hotspot)

        XCTAssertEqual(origin.y, 1_600 - PresentationCursorGeometry.renderSize + hotspot.y, accuracy: 1e-9)
        XCTAssertLessThan(origin.x, pointer.x)
        XCTAssertLessThan(origin.y, pointer.y)
    }

    // MARK: - Helpers

    private func makeImage(width: Int, height: Int) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }

    private func rgbaBytes(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    private func visiblePixelCount(_ image: CGImage) -> Int {
        rgbaBytes(image).enumerated().filter { $0.offset % 4 == 3 && $0.element > 16 }.count
    }

    /// Bounding box of everything that is actually drawn in a frame, in cell pixels.
    private func artworkBounds(_ image: CGImage) -> CGRect? {
        let width = image.width
        let pixels = rgbaBytes(image)
        var minX = width
        var minY = image.height
        var maxX = -1
        var maxY = -1
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 8 {
            let pixel = index / 4
            let x = pixel % width
            let y = pixel / width
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
