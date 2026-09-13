//
//  DefaultInputSourceTests.swift
//  Light Stats Tests
//
//  Pins the two rules that make "默认输入法" behave instead of misfire:
//
//  1. Drift is corrected *only* inside the short window after an app activation.
//     Outside it the user's own Ctrl+Space must win — otherwise the feature fights
//     the user, which is worse than the problem it solves.
//  2. Secure input (password fields) is never touched; the system pins the input
//     source there and a switch would fail anyway.
//
//  The TIS switching itself needs a real input source and a real frontmost app, so
//  it is not exercised here; this suite covers the pure decision seam plus a cheap
//  offscreen render guard for the settings row.
//

import AppKit
import Carbon
import SwiftUI
import XCTest
@testable import Light_Stats

// MARK: - Policy

final class DefaultInputSourcePolicyTests: XCTestCase {

    func testCorrectsDriftImmediatelyAfterActivation() {
        XCTAssertTrue(DefaultInputSourcePolicy.shouldCorrectDrift(
            elapsedSinceActivation: 0,
            isSecureEventInput: false
        ))
    }

    func testCorrectsDriftThroughTheWholeSettleWindow() {
        // macOS restores the per-app input source *after* didActivate fires, so the
        // window's trailing edge must still count.
        XCTAssertTrue(DefaultInputSourcePolicy.shouldCorrectDrift(
            elapsedSinceActivation: DefaultInputSourcePolicy.settleWindow,
            isSecureEventInput: false
        ))
    }

    func testLeavesDeliberateUserSwitchAloneAfterTheWindow() {
        XCTAssertFalse(DefaultInputSourcePolicy.shouldCorrectDrift(
            elapsedSinceActivation: DefaultInputSourcePolicy.settleWindow + 0.001,
            isSecureEventInput: false
        ))
        XCTAssertFalse(DefaultInputSourcePolicy.shouldCorrectDrift(
            elapsedSinceActivation: 30,
            isSecureEventInput: false
        ))
    }

    func testNeverTouchesSecureInput() {
        // Password fields: the system locks the input source, and touching it is wrong.
        XCTAssertFalse(DefaultInputSourcePolicy.shouldCorrectDrift(
            elapsedSinceActivation: 0,
            isSecureEventInput: true
        ))
        XCTAssertFalse(DefaultInputSourcePolicy.shouldCorrectDrift(
            elapsedSinceActivation: DefaultInputSourcePolicy.settleWindow,
            isSecureEventInput: true
        ))
    }

    func testRejectsNegativeElapsed() {
        XCTAssertFalse(DefaultInputSourcePolicy.shouldCorrectDrift(
            elapsedSinceActivation: -1,
            isSecureEventInput: false
        ))
    }

    /// The re-check loop is the only defence against losing the race with macOS's
    /// per-app restore, so the window must actually fit several checks.
    func testSettleWindowFitsAtLeastFourRechecks() {
        let checks = DefaultInputSourcePolicy.settleWindow / DefaultInputSourcePolicy.settleCheckInterval
        XCTAssertGreaterThanOrEqual(checks, 4)
        XCTAssertGreaterThan(DefaultInputSourcePolicy.settleCheckInterval, 0)
    }
}

// MARK: - Option normalisation

final class InputSourceOptionTests: XCTestCase {

    private func option(_ id: String, _ name: String) -> InputSourceOption {
        InputSourceOption(id: id, name: name)
    }

    func testDeduplicatesByIDKeepingFirstOccurrence() {
        let normalized = InputSourceOption.normalize([
            option("a", "Alpha"),
            option("b", "Beta"),
            option("a", "Alpha (duplicate mode)")
        ])
        XCTAssertEqual(normalized.map(\.id), ["a", "b"])
        XCTAssertEqual(normalized.first?.name, "Alpha")
    }

    func testDropsEmptyIdentifiers() {
        let normalized = InputSourceOption.normalize([
            option("", "Ghost"),
            option("a", "Alpha")
        ])
        XCTAssertEqual(normalized.map(\.id), ["a"])
    }

    func testSortsByName() {
        let normalized = InputSourceOption.normalize([
            option("c", "Charlie"),
            option("a", "Alpha"),
            option("b", "Bravo")
        ])
        XCTAssertEqual(normalized.map(\.name), ["Alpha", "Bravo", "Charlie"])
    }

    func testIdenticalNamesFallBackToIdentifierSoOrderIsStable() {
        let forward = InputSourceOption.normalize([option("z", "Same"), option("a", "Same")])
        let reversed = InputSourceOption.normalize([option("a", "Same"), option("z", "Same")])
        XCTAssertEqual(forward.map(\.id), ["a", "z"])
        XCTAssertEqual(forward, reversed)
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertTrue(InputSourceOption.normalize([]).isEmpty)
    }
}

// MARK: - Live TIS integration

/// Drives the real service end to end: observer registration → app-activation
/// notification → settle assertion → `TISSelectInputSource`.
///
/// A real frontmost-app change can't be produced inside the test host, so these post
/// `didActivateApplicationNotification` directly to the workspace notification centre;
/// the observer asserts synchronously, so no waiting is needed. Probed separately: a
/// genuine `open -a` switch does deliver that notification to a background app.
///
/// These briefly change the system input source and restore it on exit. They skip when
/// the machine doesn't have both required sources (CI runners have U.S. only).
@MainActor
final class DefaultInputSourceServiceIntegrationTests: XCTestCase {

    private let us = "com.apple.keylayout.US"
    private let weType = "com.tencent.inputmethod.wetype.pinyin"

    private func requireBothSources() throws {
        let enabledIDs = Set(DefaultInputSourceService.availableInputSources().map(\.id))
        try XCTSkipUnless(
            enabledIDs.contains(us) && enabledIDs.contains(weType),
            "Needs both U.S. and WeType enabled in System Settings"
        )
    }

    /// 测试宿主是完整 App，可能已经起了自己的默认输入法服务。先停掉它，否则它会和这组
    /// 断言抢系统输入源。`stop()` 同时清空了订阅，因此测试期间它不会自己重启。
    override func setUp() {
        super.setUp()
        DefaultInputSourceCoordinator.shared.stop()
    }

    private func select(_ id: String) {
        guard let source = DefaultInputSourceService.inputSource(withID: id) else { return }
        _ = TISSelectInputSource(source)
    }

    private func spinRunLoop(for interval: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }

    func testActivationNotificationRestoresTheTargetSource() throws {
        try requireBothSources()

        let service = DefaultInputSourceService()
        let original = try XCTUnwrap(service.currentInputSourceID())
        defer {
            service.stop()
            select(original)
        }

        select(us)
        XCTAssertEqual(service.currentInputSourceID(), us)

        service.updateTarget(id: weType)
        XCTAssertTrue(service.start())
        XCTAssertEqual(service.currentInputSourceID(), weType, "start() 应立即断言一次")

        // 模拟切到另一个 App：系统把输入源恢复成该 App 记住的那个，观察者必须拉回来。
        select(us)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        XCTAssertEqual(service.currentInputSourceID(), weType)

        // settle 窗口内的复查也要能纠正后来才发生的漂移。
        select(us)
        spinRunLoop(for: DefaultInputSourcePolicy.settleCheckInterval * 1.5)
        XCTAssertEqual(service.currentInputSourceID(), weType)
    }

    /// settle 窗口结束后不再插手：用户按 Ctrl+Space 切到英文就该留在英文。
    func testServiceLeavesDeliberateSwitchAloneAfterTheSettleWindow() throws {
        try requireBothSources()

        let service = DefaultInputSourceService()
        let original = try XCTUnwrap(service.currentInputSourceID())
        defer {
            service.stop()
            select(original)
        }

        service.updateTarget(id: weType)
        XCTAssertTrue(service.start())
        spinRunLoop(for: DefaultInputSourcePolicy.settleWindow + DefaultInputSourcePolicy.settleCheckInterval * 2)

        select(us)
        spinRunLoop(for: DefaultInputSourcePolicy.settleCheckInterval * 3)
        XCTAssertEqual(service.currentInputSourceID(), us, "settle 窗口外的漂移是用户意图，不该被改回来")
    }

    func testStartRefusesWithoutATarget() {
        let service = DefaultInputSourceService()
        defer { service.stop() }
        XCTAssertFalse(service.start())
        XCTAssertFalse(service.isRunning)
    }
}

// MARK: - Settings row render guard

@MainActor
final class DefaultInputSourceSettingsSectionTests: XCTestCase {

    private let weType = "com.tencent.inputmethod.wetype.pinyin"

    /// 渲染测试专用的隔离设置实例。
    ///
    /// **不能碰 `SettingsManager.shared`**：测试宿主就是完整 App，`AppDelegate` 已经起了
    /// 一个 `DefaultInputSourceCoordinator` 在监听 `.shared`。改 `.shared` 的开关会真的把
    /// 服务启起来，然后在别的测试跑到一半时抢走系统输入源 —— 这是实际撞到过的跨测试串扰。
    ///
    /// 实例必须留活到进程结束：macOS 14.x 上析构一个 `@MainActor` 的 `SettingsManager`
    /// 会踩 Swift Concurrency 的 back-deploy double-free（同 `SettingsDefaultsTests`）。
    private static var retained: [SettingsManager] = []
    /// 固定一个 suite，不要每次新建 UUID 域——每个域都会在 ~/Library/Preferences 里留一个 plist。
    private static let suiteName = "LightStatsTests.DefaultInputSourceSettings"
    private var cleanDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        cleanDefaults = UserDefaults(suiteName: Self.suiteName)
        cleanDefaults.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        cleanDefaults.removePersistentDomain(forName: Self.suiteName)
        cleanDefaults = nil
        super.tearDown()
    }

    private func isolatedSettings() -> SettingsManager {
        let settings = SettingsManager(defaults: cleanDefaults)
        Self.retained.append(settings)
        return settings
    }

    func testUnavailableSelectionStaysVisibleInThePicker() {
        let options = [InputSourceOption(id: "com.apple.keylayout.US", name: "U.S.")]
        let merged = DefaultInputSourceSettingsSection.pickerOptions(
            available: options,
            storedID: weType,
            unavailableName: "Unavailable"
        )
        XCTAssertEqual(merged.first?.id, weType)
        XCTAssertEqual(merged.first?.name, "Unavailable")
        XCTAssertEqual(merged.count, 2)
    }

    func testAvailableSelectionIsNotDuplicated() {
        let options = [
            InputSourceOption(id: weType, name: "微信输入法"),
            InputSourceOption(id: "com.apple.keylayout.US", name: "U.S.")
        ]
        let merged = DefaultInputSourceSettingsSection.pickerOptions(
            available: options,
            storedID: weType,
            unavailableName: "Unavailable"
        )
        XCTAssertEqual(merged, options)
    }

    func testNoStoredSelectionLeavesTheListAlone() {
        let options = [InputSourceOption(id: "com.apple.keylayout.US", name: "U.S.")]
        XCTAssertEqual(
            DefaultInputSourceSettingsSection.pickerOptions(
                available: options,
                storedID: nil,
                unavailableName: "Unavailable"
            ),
            options
        )
    }

    /// 真实 TIS 枚举：只应拿到可选（select-capable）的键盘布局与输入法模式。
    /// `com.tencent.inputmethod.wetype` 这类父 mode 与子 mode 同名，如果不按
    /// `IsSelectCapable` 过滤，选择器里会出现两条一模一样的「微信输入法」。
    func testAvailableSourcesExcludeNonSelectableParentModes() {
        let options = DefaultInputSourceService.availableInputSources()
        XCTAssertFalse(options.isEmpty, "Expected the host to have at least one enabled input source")
        XCTAssertFalse(options.contains { $0.id == "com.tencent.inputmethod.wetype" })
        XCTAssertFalse(options.contains { $0.id == "com.apple.CharacterPaletteIM" })
        XCTAssertEqual(options.map(\.id).count, Set(options.map(\.id)).count)
    }

    /// Renders the row offscreen so a layout/composition regression (a Picker that
    /// cannot resolve its tag, a missing localization key, a crash on the
    /// `@ObservedObject` default) fails the suite instead of shipping.
    func testSettingsRowRendersWithARealSelection() throws {
        let settings = isolatedSettings()

        DefaultInputSourceCoordinator.shared.refreshAvailableSources()
        let options = DefaultInputSourceCoordinator.shared.availableSources
        let target = options.first { $0.id == weType } ?? options[0]

        settings.defaultInputSourceEnabled = true
        settings.defaultInputSourceID = target.id

        let content = VStack(spacing: 12) {
            DefaultInputSourceSettingsSection(settings: settings)
        }
        .padding(16)
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .appThemed(AppTheme.glass)

        let hostingView = NSHostingView(rootView: content)
        let size = hostingView.fittingSize
        hostingView.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 0)
        try png.write(to: URL(fileURLWithPath: "/tmp").appendingPathComponent("default-input-source-row.png"))
    }
}
