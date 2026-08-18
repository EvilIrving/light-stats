import AppKit
import SwiftUI
import XCTest
@testable import Light_Stats

@MainActor
final class VisualThemeCaptureTests: XCTestCase {
    func testCaptureThemesForVisualReview() throws {
        let settings = SettingsManager.shared
        let originalTheme = settings.appTheme
        let originalLanguage = settings.appLanguage
        let originalFilmGrainEnabled = settings.filmGrainEnabled
        let originalFilmLightFlow = settings.filmLightFlow
        let originalBarGrainEnabled = settings.barGrainEnabled
        let originalBarLightFlow = settings.barLightFlow
        let originalNoirGrainEnabled = settings.noirGrainEnabled
        let originalNoirLightFlow = settings.noirLightFlow
        let originalExitNodeDetectionEnabled = settings.exitNodeDetectionEnabled
        let originalClaudeEnabled = settings.aiMonitorClaudeEnabled
        let originalCodexEnabled = settings.aiMonitorCodexEnabled
        let originalGeminiEnabled = settings.aiMonitorGeminiEnabled
        let appMemoryManager = AppMemoryManager.shared
        let originalRunningApps = appMemoryManager.runningApps
        let originalTotalMemoryUsed = appMemoryManager.totalMemoryUsed
        let originalTotalMemory = appMemoryManager.totalMemory
        let originalAppCount = appMemoryManager.appCount
        let originalMemoryPressure = appMemoryManager.memoryPressure
        defer {
            settings.appTheme = originalTheme
            settings.appLanguage = originalLanguage
            settings.filmGrainEnabled = originalFilmGrainEnabled
            settings.filmLightFlow = originalFilmLightFlow
            settings.barGrainEnabled = originalBarGrainEnabled
            settings.barLightFlow = originalBarLightFlow
            settings.noirGrainEnabled = originalNoirGrainEnabled
            settings.noirLightFlow = originalNoirLightFlow
            settings.exitNodeDetectionEnabled = originalExitNodeDetectionEnabled
            settings.aiMonitorClaudeEnabled = originalClaudeEnabled
            settings.aiMonitorCodexEnabled = originalCodexEnabled
            settings.aiMonitorGeminiEnabled = originalGeminiEnabled
            appMemoryManager.runningApps = originalRunningApps
            appMemoryManager.totalMemoryUsed = originalTotalMemoryUsed
            appMemoryManager.totalMemory = originalTotalMemory
            appMemoryManager.appCount = originalAppCount
            appMemoryManager.memoryPressure = originalMemoryPressure
            LocalizationManager.shared.setLanguage(originalLanguage)
            SystemMonitor.shared.setPopoverVisible(false)
        }

        settings.appLanguage = .en
        settings.filmGrainEnabled = true
        settings.filmLightFlow = 0
        settings.barGrainEnabled = true
        settings.barLightFlow = 0
        settings.noirGrainEnabled = true
        settings.noirLightFlow = 0
        settings.exitNodeDetectionEnabled = false
        settings.aiMonitorClaudeEnabled = false
        settings.aiMonitorCodexEnabled = false
        settings.aiMonitorGeminiEnabled = false
        applySafeMemoryFixture(to: appMemoryManager)
        LocalizationManager.shared.setLanguage(.en)
        SystemMonitor.shared.setPopoverVisible(true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        try capture(.glass, filename: "system-glass-panel.png")
        try capture(.glass, initialTab: 1, filename: "system-glass-cleanup-panel.png")
        try capture(.film, filename: "neon-panel.png")
        try capture(.film, initialTab: 1, filename: "neon-cleanup-panel.png")
        try capture(.bar, filename: "night-bar-panel.png")
        try capture(.bar, initialTab: 1, filename: "night-bar-cleanup-panel.png")
        try capture(.noir, filename: "ink-night-panel.png")
        try capture(.noir, initialTab: 1, filename: "ink-night-cleanup-panel.png")
        try capture(.dataPaper, filename: "data-paper-panel.png")
    }

    private func applySafeMemoryFixture(to manager: AppMemoryManager) {
        manager.stopMonitoring()
        manager.runningApps = screenshotAppFixtures()
        manager.totalMemoryUsed = 17_716_740_608
        manager.totalMemory = 34_359_738_368
        manager.appCount = manager.runningApps.count
        manager.memoryPressure = .normal
    }

    private func screenshotAppFixtures() -> [AppGroup] {
        let fixtures: [(String, String, UInt64, Int)] = [
            ("Browser", "safari", 3_758_096_384, 18),
            ("Code Editor", "chevron.left.forwardslash.chevron.right", 2_362_232_832, 12),
            ("Terminal", "terminal", 1_503_238_144, 8),
            ("Design Tool", "paintbrush", 1_073_741_824, 6),
            ("Chat", "message", 751_619_277, 5),
            ("Files", "folder", 536_870_912, 3)
        ]
        return fixtures.enumerated().map { index, fixture in
            AppGroup(
                id: pid_t(index + 10_000),
                name: fixture.0,
                icon: NSImage(systemSymbolName: fixture.1, accessibilityDescription: nil) ?? NSImage(),
                totalMemoryBytes: fixture.2,
                processCount: fixture.3,
                allPids: [pid_t(index + 10_000)],
                terminablePids: [pid_t(index + 10_000)],
                isTerminable: true,
                bundleIdentifier: nil,
                bundlePath: nil,
                execPath: nil
            )
        }
    }

    private func capture(
        _ theme: AppTheme,
        initialTab: Int = 0,
        filename: String
    ) throws {
        SettingsManager.shared.appTheme = theme
        let content = PopoverContentView(initialTab: initialTab)
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
        defer { window.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        if initialTab == 1 {
            applySafeMemoryFixture(to: AppMemoryManager.shared)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
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
