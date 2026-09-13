//
//  DefaultInputSourceService.swift
//  Light Stats
//
//  强制「默认输入法」：每个 App 激活后把当前输入源拉回用户选定的那一个。
//
//  为什么必须主动断言：macOS 只有 Text Input Source 层的 per-App 记忆（切回某个 App
//  时恢复它上次用过的输入源），没有「全局默认输入法」这个开关。所以不存在一个系统设置
//  能让它不跳，只能由常驻进程在激活事件后覆盖。
//
//  为什么不常驻轮询：用户按 Ctrl+Space 手动切到英文同样表现为「漂移」，常驻轮询会在
//  一两秒内把它抢回来，比不修更烦人。因此只在 App 激活后的短暂窗口内修正 —— 那个窗口
//  里的漂移几乎一定是系统恢复 per-App 记忆造成的。见 `DefaultInputSourcePolicy`。
//

import AppKit
import Carbon
import Foundation

/// 漂移修正时机。纯逻辑，是回归测试的接缝。
nonisolated enum DefaultInputSourcePolicy {
    /// App 激活后仍视为「系统恢复了该 App 记住的输入源」的时间窗。
    ///
    /// 1.2s 是权衡值：再长会开始抢用户在这个窗口内主动按下的 Ctrl+Space；再短则
    /// 覆盖不到 macOS 恢复 per-App 输入源的时机（实测晚于 didActivate 通知）。
    static let settleWindow: TimeInterval = 1.2

    /// 窗口内的复查间隔。单次调用会输给系统的 per-App 恢复，窗口内需要复查若干次。
    static let settleCheckInterval: TimeInterval = 0.25

    /// 是否应当把输入源拉回目标值。
    ///
    /// - Parameters:
    ///   - elapsedSinceActivation: 距最近一次 App 激活的秒数。
    ///   - isSecureEventInput: 密码框等安全输入是否进行中。安全输入期间系统会锁住
    ///     输入源，切换必然失败，而且此处也不该切。
    static func shouldCorrectDrift(elapsedSinceActivation: TimeInterval, isSecureEventInput: Bool) -> Bool {
        guard elapsedSinceActivation >= 0 else { return false }
        guard !isSecureEventInput else { return false }
        return elapsedSinceActivation <= settleWindow
    }
}

@MainActor
protocol DefaultInputSourceControlling: AnyObject {
    var isRunning: Bool { get }
    /// 返回 false 表示目标未选定（或输入法已被移除），调用方应保持开关状态但视为未运行。
    func start() -> Bool
    func stop()
    func updateTarget(id: String?)
    /// 用户主动触发（开启开关 / 换目标 / 启动时同步）：立刻断言一次，不等下一次 App 切换。
    func applyNow()
    func currentInputSourceID() -> String?
}

@MainActor
final class DefaultInputSourceService: DefaultInputSourceControlling {

    private let log = AppLogger(category: "DefaultInputSource")

    private(set) var isRunning = false
    private var targetID: String?
    private var activationObserver: NSObjectProtocol?
    private var settleTimer: Timer?
    /// 最近一次 App 激活的单调时刻，用于判断是否还在 settle 窗口内。
    private var activatedAt: TimeInterval = -.infinity

    // MARK: - Lifecycle

    func start() -> Bool {
        guard !isRunning else { return true }
        guard targetID?.isEmpty == false else { return false }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginSettleWindow() }
        }
        isRunning = true
        beginSettleWindow()
        return true
    }

    func stop() {
        isRunning = false
        invalidateSettleTimer()
        removeActivationObserver()
    }

    func updateTarget(id: String?) {
        targetID = id
    }

    func applyNow() {
        guard isRunning else { return }
        assertTarget(trigger: "explicit")
    }

    // MARK: - Settle window

    /// App 激活：开一个 settle 窗口，窗口内反复确认输入源没被系统改回去。
    private func beginSettleWindow() {
        guard isRunning else { return }
        activatedAt = ProcessInfo.processInfo.systemUptime
        assertTarget(trigger: "activation")
        guard settleTimer == nil else { return }

        let timer = Timer(timeInterval: DefaultInputSourcePolicy.settleCheckInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated { self?.settleTick(timer) }
        }
        // .common 模式：菜单展开 / 拖拽滚动期间也要继续跑，否则窗口会被推迟到交互结束。
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    private func settleTick(_ timer: Timer) {
        let elapsed = ProcessInfo.processInfo.systemUptime - activatedAt
        guard DefaultInputSourcePolicy.shouldCorrectDrift(
            elapsedSinceActivation: elapsed,
            isSecureEventInput: IsSecureEventInputEnabled()
        ) else {
            // 窗口结束（或进入安全输入）：停止复查。之后出现的漂移一律当作用户的主动切换。
            invalidateSettleTimer()
            return
        }
        assertTarget(trigger: "settle")
    }

    private func invalidateSettleTimer() {
        settleTimer?.invalidate()
        settleTimer = nil
    }

    private func removeActivationObserver() {
        guard let activationObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        self.activationObserver = nil
    }

    // MARK: - Switching

    /// 只在当前输入源与目标不一致时才切。对当前输入源重复调用 `TISSelectInputSource`
    /// 是无意义的状态抖动，会连带刷 UI 与通知。
    private func assertTarget(trigger: String) {
        guard isRunning, let targetID else { return }
        guard !IsSecureEventInputEnabled() else { return }
        guard currentInputSourceID() != targetID else { return }
        guard selectInputSource(id: targetID) else {
            log.error("Default input source \(targetID) unavailable (\(trigger))")
            return
        }
        log.info("Restored input source to \(targetID) (\(trigger))")
    }

    private func selectInputSource(id: String) -> Bool {
        guard let source = Self.inputSource(withID: id) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return Self.string(of: source, key: kTISPropertyInputSourceID)
    }

    // MARK: - Text Input Sources (static, nonisolated)

    /// 当前已启用且可选的输入源（键盘布局 + 输入法模式），已去重排序。
    ///
    /// 传 `includeAllInstalled: false` 只拿已启用的：未启用的项选不中，列进选单只会误导。
    nonisolated static func availableInputSources() -> [InputSourceOption] {
        let selectableTypes: Set<String> = [
            kTISTypeKeyboardLayout as String,
            kTISTypeKeyboardInputMode as String
        ]
        let options = enumerateInstalled().compactMap { source -> InputSourceOption? in
            guard let type = string(of: source, key: kTISPropertyInputSourceType),
                  selectableTypes.contains(type),
                  bool(of: source, key: kTISPropertyInputSourceIsSelectCapable),
                  let id = string(of: source, key: kTISPropertyInputSourceID)
            else { return nil }
            return InputSourceOption(
                id: id,
                name: string(of: source, key: kTISPropertyLocalizedName) ?? id
            )
        }
        return InputSourceOption.normalize(options)
    }

    nonisolated static func inputSource(withID id: String) -> TISInputSource? {
        let query = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(query, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.first
    }

    /// `includeAllInstalled: false` → 只含已启用、可选的输入源。
    nonisolated private static func enumerateInstalled() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list
    }

    nonisolated private static func string(of source: TISInputSource, key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    nonisolated private static func bool(of source: TISInputSource, key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }
}
