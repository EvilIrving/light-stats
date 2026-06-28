//
//  UsageWarmupManager.swift
//  Light Stats
//
//  Created on 2026/06/28.
//
//  Drives "warmup" sends that anchor the rolling usage window for opt-in providers.
//  Kept fully independent of AIUsageMonitor (which stays read-only): this class only
//  *reads* the monitor's published snapshots to learn each provider's reset time, and
//  never feeds back into it. Default-off — nothing runs until a per-provider switch is on.
//
//  Per-provider loop (see WarmupSchedule for the policy):
//   1. On enable: one health-probe send (validates the CLI is installed + logged in).
//      Fail → log and stop (no scheduling). Success → enter the loop.
//   2. Loop: read the rolling-window reset from the monitor, sleep until reset+δ
//      (in ≤60s chunks so system sleep/wake self-corrects), then send to anchor a
//      fresh window. Dedup via lastAnchoredReset so a slow monitor refresh can't
//      double-send for the same window.
//   3. On wake: cancel + re-evaluate immediately so an expired window is caught up.
//

import Foundation
import Combine
import AppKit
import os

@MainActor
final class UsageWarmupManager: ObservableObject {

    static let shared = UsageWarmupManager()

    /// 仅这两家有滚动窗口；Gemini 是每日 quota，不参与。
    private static let supported: [AIProvider] = [.claude, .codex]

    private let settings = SettingsManager.shared
    private let monitor = AIUsageMonitor.shared
    private let log = Logger(subsystem: "com.lightstats.app", category: "UsageWarmup")

    private var loops: [AIProvider: Task<Void, Never>] = [:]
    private var lastAnchoredReset: [AIProvider: Date] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var wakeObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        // 开关或对应监控状态变化 → 重新评估每个 provider（开 → 起循环；关 → 立即停）。
        Publishers.CombineLatest4(
            settings.$autoRefreshClaudeEnabled,
            settings.$autoRefreshCodexEnabled,
            settings.$aiMonitorClaudeEnabled,
            settings.$aiMonitorCodexEnabled
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.syncAll() }
        .store(in: &cancellables)

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }

        syncAll()
    }

    /// Runtime off-path: tear everything down immediately (not only at terminate).
    func stopAll() {
        for provider in Self.supported { stop(provider) }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        cancellables.removeAll()
    }

    // MARK: - Per-provider lifecycle

    /// warmup 需要该 provider 的监控也开着（reset 时间来自监控快照）。
    private func isEnabled(_ provider: AIProvider) -> Bool {
        switch provider {
        case .claude: return settings.autoRefreshClaudeEnabled && settings.aiMonitorClaudeEnabled
        case .codex: return settings.autoRefreshCodexEnabled && settings.aiMonitorCodexEnabled
        case .gemini: return false
        }
    }

    private func syncAll() {
        for provider in Self.supported {
            if isEnabled(provider) { start(provider) } else { stop(provider) }
        }
    }

    private func start(_ provider: AIProvider) {
        guard loops[provider] == nil else { return }   // 已在跑，避免重复起循环
        log.info("warmup loop start: \(provider.rawValue, privacy: .public)")
        loops[provider] = Task { [weak self] in
            await self?.run(provider)
        }
    }

    private func stop(_ provider: AIProvider) {
        guard let task = loops[provider] else { return }
        task.cancel()
        loops[provider] = nil
        lastAnchoredReset[provider] = nil
        log.info("warmup loop stop: \(provider.rawValue, privacy: .public)")
    }

    /// 唤醒后立即重判：取消正在睡眠的循环、重新起，让已过期窗口尽快补发。
    private func handleWake() {
        for provider in Self.supported where loops[provider] != nil {
            stop(provider)
        }
        syncAll()
    }

    // MARK: - Loop

    private func run(_ provider: AIProvider) async {
        // 启用即做一次健康探测（同时也是一次 warmup 尝试）。
        // 失败＝CLI 不可用 / 未登录 → 记日志、不再排程（不打扰用户、不无限重试）。
        let healthy = await UsageWarmupService.send(provider: provider)
        guard healthy else {
            log.error("warmup disabled (CLI unavailable/not logged in): \(provider.rawValue, privacy: .public)")
            loops[provider] = nil
            return
        }

        while !Task.isCancelled {
            let reset = rollingReset(for: provider)
            switch WarmupSchedule.decide(now: Date(),
                                         reset: reset,
                                         lastAnchoredReset: lastAnchoredReset[provider]) {
            case .waitForWindow:
                try? await Task.sleep(for: .seconds(60))
            case .sleep(let seconds):
                try? await Task.sleep(for: .seconds(seconds))
            case .sendNow:
                _ = await UsageWarmupService.send(provider: provider)
                lastAnchoredReset[provider] = reset
                try? await Task.sleep(for: .seconds(90))   // 给监控时间刷新到新窗口
            }
        }
    }

    /// 当前滚动窗口的 reset：取快照里最早的 reset（滚动窗口比周窗口先重置）。可能略早于 now。
    private func rollingReset(for provider: AIProvider) -> Date? {
        let state: ProviderFetchState
        switch provider {
        case .claude: state = monitor.claudeState
        case .codex: state = monitor.codexState
        case .gemini: return nil
        }
        guard let snapshot = state.snapshot else { return nil }
        return snapshot.windows.compactMap(\.resetsAt).min()
    }
}
