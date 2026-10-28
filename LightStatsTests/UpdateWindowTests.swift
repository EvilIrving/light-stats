import AppKit
import SwiftUI
import XCTest
@testable import Light_Stats

@MainActor
final class UpdateWindowTests: XCTestCase {
    func testPhaseChangesKeepWindowStableAndInterruptedInstallShowsFeedback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let attempts = UpdateAttemptService(directory: directory)
        let manager = UpdateManager(attempts: attempts)
        defer { manager.dismissWindow() }
        // A local unsupported URL exercises failure without making any network request or installing an app.
        let json: [String: Any] = [
            "tag_name": "v999.0.0", "body": String(repeating: "更新说明 • Release notes 日本語 한국어\n", count: 80),
            "html_url": "https://github.com/EvilIrving/light-stats/releases/tag/v999.0.0",
            "assets": [["name": "fixture.dmg", "browser_download_url": "file:///nonexistent-light-stats-test.dmg"]]
        ]
        let release = try XCTUnwrap(ReleaseInfo(json: JSONSerialization.data(withJSONObject: json)))
        manager.handle(release: release, userInitiated: true)
        try await Task.sleep(for: .milliseconds(150))
        let window = try XCTUnwrap(manager.window)
        let frame = try await settledFrame(of: window)
        XCTAssertNotNil(window.contentViewController)
        // The window must be the size the geometry decided on, not whatever size
        // the hosting view's fitting pass happened to leave behind — assigning
        // `contentViewController` resizes the window to that fitting size, and a
        // later pass (or the `maxSize` clamp) used to move it by 2 pt.
        let chrome = Self.chromeHeight(for: window.styleMask)
        let visibleHeight = (window.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame.height
        XCTAssertEqual(
            window.contentLayoutRect.height,
            UpdateWindowGeometry.contentHeight(visibleHeight: visibleHeight, chromeHeight: chrome),
            accuracy: 1,
            "the update window keeps the content height the geometry chose"
        )
        XCTAssertEqual(window.contentLayoutRect.width, UpdateWindowGeometry.contentWidth, accuracy: 1)
        try capture(window, name: "available")

        manager.startInstall(release)
        manager.startInstall(release)
        manager.dismissWindow()
        XCTAssertTrue(manager.isInstalling)
        XCTAssertTrue(manager.window === window)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while manager.isInstalling, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(manager.isInstalling)
        guard case .error = manager.phase else { return XCTFail("Expected local download failure") }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(window.frame, frame)
        try capture(window, name: "error")

        try await attempts.begin(sourceVersion: "1.9.2-beta.7", release: release, destination: Bundle.main.bundleURL)
        try await attempts.advance(to: "replacing")
        let resultURL = await attempts.resultURL
        try "replace-failed".write(to: resultURL, atomically: true, encoding: .utf8)
        let recovered = await manager.recoverInterruptedUpdate()
        XCTAssertTrue(recovered)
        guard case .error(let message) = manager.phase else { return XCTFail("Missing recovery feedback") }
        XCTAssertTrue(message.contains("v999.0.0"))
        XCTAssertEqual(manager.downloadPage, release.htmlURL)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(window.frame, frame)
        try capture(window, name: "recovery")
        let pending = try await attempts.pending(for: Bundle.main.bundleURL)
        XCTAssertNil(pending)
    }

    func testManualCheckAndLaunchCheckShareLocalRecoveryBeforeNetworking() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let attempts = UpdateAttemptService(directory: directory)
        let release = try XCTUnwrap(ReleaseInfo(manifest: Data(#"{"version":"999.0.0","file":"fixture.dmg"}"#.utf8)))
        try await attempts.begin(sourceVersion: "1.9.3", release: release, destination: Bundle.main.bundleURL)
        await attempts.releaseOwnership()
        let manager = UpdateManager(attempts: UpdateAttemptService(directory: directory))
        defer { manager.dismissWindow() }
        manager.check(userInitiated: true)
        manager.checkOnLaunch()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while manager.isChecking, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(manager.isChecking)
        guard case .error(let message) = manager.phase else { return XCTFail("Local update result was skipped") }
        XCTAssertTrue(message.contains("v999.0.0"))
        XCTAssertNotNil(manager.window)
        let pending = try await attempts.pending(for: Bundle.main.bundleURL)
        XCTAssertNil(pending)
    }

    /// Window 的帧在创建阶段会被 AppKit 改两次：给 `contentViewController` 赋值会把窗口改成
    /// hosting view 的 fitting size，随后 AppKit 再布局一次，还可能被 `maxSize` 夹一次。三者
    /// 的时机关机器快慢而不同（CI 上实测差 2pt，本机差 0），所以基线必须取真正停下来的帧。
    ///
    /// 产品侧已把尺寸在赋值之后显式钉住（`UpdateManager.showUpdateWindow`），这里仍要求
    /// 「连续若干次采样都不变且窗口已上屏」：单次相等会把布局过程里的停顿当成已就位。
    private func settledFrame(
        of window: NSWindow,
        quietSamples: Int = 4,
        timeout: Duration = .seconds(3)
    ) async throws -> NSRect {
        var previous = window.frame
        var stable = 0
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            let current = window.frame
            if current == previous, window.isVisible {
                stable += 1
                if stable >= quietSamples { return current }
            } else {
                stable = 0
            }
            previous = current
        }
        return previous
    }

    private static func chromeHeight(for styleMask: NSWindow.StyleMask) -> CGFloat {
        let probe = NSRect(x: 0, y: 0, width: UpdateWindowGeometry.contentWidth, height: 100)
        return NSWindow.frameRect(forContentRect: probe, styleMask: styleMask).height - probe.height
    }

    private func capture(_ window: NSWindow, name: String) throws {
        let view = try XCTUnwrap(window.contentView)
        view.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "update-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        try data.write(to: URL(fileURLWithPath: "/tmp/light-stats-update-\(name).png"))
    }
}
