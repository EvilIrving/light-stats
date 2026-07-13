import AppKit
import SwiftUI
import XCTest
@testable import Light_Stats

@MainActor
final class VisualThemeCaptureTests: XCTestCase {
    func testCaptureStaticThemesForVisualReview() throws {
        let settings = SettingsManager.shared
        let originalTheme = settings.appTheme
        let originalLanguage = settings.appLanguage
        defer {
            settings.appTheme = originalTheme
            settings.appLanguage = originalLanguage
        }

        settings.appLanguage = .en
        LocalizationManager.shared.setLanguage(.en)
        SystemMonitor.shared.setPopoverVisible(true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        try capture(.film, filename: "sun-gold-panel.png")
        try capture(.noir, filename: "ink-night-panel.png")
    }

    private func capture(_ theme: AppTheme, filename: String) throws {
        SettingsManager.shared.appTheme = theme
        let content = PopoverContentView()
            .environmentObject(SystemMonitor.shared)
            .environmentObject(AIUsageMonitor.shared)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(origin: .zero, size: PopoverContentView.canvasSize)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(PopoverContentView.canvasSize.width * 2),
            pixelsHigh: Int(PopoverContentView.canvasSize.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = hostingView.bounds.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(filename)
        try png.write(to: url)
    }
}
