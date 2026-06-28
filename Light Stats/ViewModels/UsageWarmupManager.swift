//
//  UsageWarmupManager.swift
//  Light Stats
//
//  Created on 2026/06/28.
//
//  目标很简单：对开了「自动续期窗口」的 provider，每隔固定时长发一条无害消息——
//  就是把用户手动用 `/loop` 每 4 小时 ping 一次的事做成内置。不做任何「按 reset 时刻
//  对齐 / 提前 anchor」的花活：一个计时器 + 一个 Task，定时发，仅此而已。
//
//  每 provider 一个循环：启用即发一次（兼 CLI 登录态健康探测），失败则记日志、停；
//  成功则每 interval 发一次。睡眠用 ≤60s 分块轮询，系统睡眠唤醒后墙钟自校正（漏发尽快补上）。
//  默认全关——干净安装什么都不跑。
//

import Foundation
import Combine
import os

@MainActor
final class UsageWarmupManager: ObservableObject {

    static let shared = UsageWarmupManager()

    /// 仅这两家有滚动窗口；Gemini 是每日 quota，不参与。
    private static let supported: [AIProvider] = [.claude, .codex]

    /// 固定发送间隔：每 4 小时发一条（< 5h 窗口，保证持续覆盖）。
    private static let interval: TimeInterval = 4 * 3600

    private let settings = SettingsManager.shared
    private let log = Logger(subsystem: "com.lightstats.app", category: "UsageWarmup")

    private var loops: [AIProvider: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Lifecycle

    func start() {
        // 开关或对应监控状态变化 → 重新评估（开 → 起循环；关 → 立即停）。
        Publishers.CombineLatest4(
            settings.$autoRefreshClaudeEnabled,
            settings.$autoRefreshCodexEnabled,
            settings.$aiMonitorClaudeEnabled,
            settings.$aiMonitorCodexEnabled
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.syncAll() }
        .store(in: &cancellables)

        syncAll()
    }

    /// Runtime off-path: tear everything down immediately (not only at terminate).
    func stopAll() {
        for provider in Self.supported { stop(provider) }
        cancellables.removeAll()
    }

    // MARK: - Per-provider lifecycle

    /// warmup 需要该 provider 的监控也开着（开关只在监控开启时才出现）。
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
        log.info("warmup loop stop: \(provider.rawValue, privacy: .public)")
    }

    // MARK: - Loop

    private func run(_ provider: AIProvider) async {
        // 启用即发一次（同时是 CLI 登录态健康探测）。失败 → 记日志、不再排程（不打扰、不无限重试）。
        let healthy = await UsageWarmupService.send(provider: provider)
        guard healthy else {
            log.error("warmup disabled (CLI unavailable/not logged in): \(provider.rawValue, privacy: .public)")
            loops[provider] = nil
            return
        }

        while !Task.isCancelled {
            await sleepInterval()
            if Task.isCancelled { break }
            _ = await UsageWarmupService.send(provider: provider)
        }
    }

    /// 睡满一个 interval，分 ≤60s 块轮询：系统睡眠会冻住单次 sleep，但唤醒后用墙钟
    /// 重新比对截止时间，漏过的 ping 会在唤醒后尽快补发，不会一直拖到下一整段。
    private func sleepInterval() async {
        let deadline = Date().addingTimeInterval(Self.interval)
        while Date() < deadline {
            if Task.isCancelled { return }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(min(remaining, 60)))
        }
    }
}
