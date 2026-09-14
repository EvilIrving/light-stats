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
//  The TIS switching itself needs a real input source, a real frontmost app, and it
//  mutates the machine's input source, so it is not exercised here; this suite covers
//  the pure decision seams (policy, option normalisation, picker merge) only.
//

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

// MARK: - Service guard

/// `start()` 在没有选定目标源时必须拒绝启动，否则会误切到用户没挑过的源。
/// 这里不注册 observer、不碰 TIS，纯状态判断，所以留在单元测试里。
@MainActor
final class DefaultInputSourceServiceTests: XCTestCase {

    func testStartRefusesWithoutATarget() {
        let service = DefaultInputSourceService()
        defer { service.stop() }
        XCTAssertFalse(service.start())
        XCTAssertFalse(service.isRunning)
    }
}

// MARK: - Settings section

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
}
