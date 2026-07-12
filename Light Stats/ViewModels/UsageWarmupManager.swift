//
//  UsageWarmupManager.swift
//  Light Stats
//
//  Created on 2026/06/28.
//
//  目标很简单：对开了「自动续期窗口」的 provider，在 5h 窗口 reset 后发一条无害消息——
//  就是把用户手动等窗口过期后 ping 一次的事做成内置。mid-window 发送不会移动 reset，
//  所以这里必须先拿到当前窗口 reset，再在 reset 后短延迟触发。
//
//  每 provider 一个循环：拿 reset → 等到 reset+delay → 发送 → 刷新验证；同一个 reset
//  只发一次，避免服务端短暂返回旧窗口时重复消耗。默认全关——干净安装什么都不跑。
//

import Foundation
import Combine
import os

@MainActor
final class UsageWarmupManager: ObservableObject {

    static let shared = UsageWarmupManager()

    /// 仅这两家有滚动窗口；Gemini 是每日 quota，不参与。
    private static let supported: [AIProvider] = [.claude, .codex]

    private static let resetDelay: TimeInterval = 60
    private static let snapshotRetryDelay: TimeInterval = 2 * 3600
    private static let retryDelays: [TimeInterval] = [30, 120]

    private let settings = SettingsManager.shared
    private let log = AppLogger(category: "UsageWarmup", mirrorsToJournal: false)

    private var loops: [AIProvider: Task<Void, Never>] = [:]
    private var lastSentReset: [AIProvider: Date] = [:]
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
        log.info("warmup loop start: \(provider.rawValue)")
        DiagnosticLogService.record(category: "usageWarmup", action: "loopStarted", fields: providerFields(provider))
        loops[provider] = Task { [weak self] in
            await self?.run(provider)
        }
    }

    private func stop(_ provider: AIProvider) {
        guard let task = loops[provider] else { return }
        task.cancel()
        loops[provider] = nil
        lastSentReset[provider] = nil
        log.info("warmup loop stop: \(provider.rawValue)")
        DiagnosticLogService.record(category: "usageWarmup", action: "loopStopped", fields: providerFields(provider))
    }

    // MARK: - Loop

    private func run(_ provider: AIProvider) async {
        while !Task.isCancelled {
            guard let fireDate = await nextFireDate(for: provider) else {
                log.error("warmup waiting for readable 5h reset: \(provider.rawValue)")
                DiagnosticLogService.record(
                    level: .error,
                    category: "usageWarmup",
                    action: "resetUnavailable",
                    fields: providerFields(provider)
                )
                await sleep(seconds: Self.snapshotRetryDelay)
                continue
            }

            log.info(
                "warmup scheduled \(provider.rawValue) at \(fireDate)"
            )
            DiagnosticLogService.record(
                category: "usageWarmup",
                action: "scheduled",
                fields: providerFields(provider).merging(["fireDate": fireDate.ISO8601Format()]) { _, new in new }
            )
            await sleep(until: fireDate)
            if Task.isCancelled { break }

            let reset = fireDate.addingTimeInterval(-Self.resetDelay)
            if await sendWithRetries(provider) {
                lastSentReset[provider] = reset
                await verifySend(provider, previousReset: reset)
            } else {
                await sleep(seconds: Self.snapshotRetryDelay)
            }
        }
    }

    private func nextFireDate(for provider: AIProvider) async -> Date? {
        do {
            let snapshot = try await fetchUsage(provider)
            return Self.nextFireDate(
                from: snapshot,
                now: Date(),
                resetDelay: Self.resetDelay,
                lastSentReset: lastSentReset[provider]
            )
        } catch {
            let description = String(describing: error)
            log.error(
                "warmup usage fetch failed for \(provider.rawValue): \(description)"
            )
            DiagnosticLogService.record(
                level: .error,
                category: "usageWarmup",
                action: "usageFetchFailed",
                fields: providerFields(provider).merging(["error": description]) { _, new in new }
            )
            return nil
        }
    }

    private func fetchUsage(_ provider: AIProvider) async throws -> ProviderUsageSnapshot {
        switch provider {
        case .claude: return try await ClaudeUsageService.fetch()
        case .codex: return try await CodexUsageService.fetch()
        case .gemini: throw AIUsageError.decoding
        }
    }

    private func sendWithRetries(_ provider: AIProvider) async -> Bool {
        for attempt in 0...Self.retryDelays.count {
            if await UsageWarmupService.send(provider: provider) {
                return true
            }

            guard attempt < Self.retryDelays.count else { break }
            let delay = Self.retryDelays[attempt]
            let retryNumber = attempt + 1
            let seconds = Int(delay)
            log.error(
                "warmup retry \(provider.rawValue) #\(retryNumber) in \(seconds)s"
            )
            DiagnosticLogService.record(
                level: .warning,
                category: "usageWarmup",
                action: "retryScheduled",
                fields: providerFields(provider).merging([
                    "retryNumber": String(retryNumber), "delaySeconds": String(seconds)
                ]) { _, new in new }
            )
            await sleep(seconds: delay)
            if Task.isCancelled { return false }
        }

        log.error("warmup failed after retries for \(provider.rawValue)")
        DiagnosticLogService.record(
            level: .error,
            category: "usageWarmup",
            action: "failedAfterRetries",
            fields: providerFields(provider)
        )
        return false
    }

    private func verifySend(_ provider: AIProvider, previousReset: Date) async {
        do {
            let snapshot = try await fetchUsage(provider)
            guard let nextReset = Self.primaryReset(in: snapshot),
                  nextReset > previousReset else {
                log.error("warmup sent but reset did not advance/read back yet: \(provider.rawValue)")
                DiagnosticLogService.record(
                    level: .error,
                    category: "usageWarmup",
                    action: "verificationDidNotAdvance",
                    fields: providerFields(provider)
                )
                return
            }
            log.info("warmup verified \(provider.rawValue) nextReset=\(nextReset)")
            DiagnosticLogService.record(
                category: "usageWarmup",
                action: "verified",
                fields: providerFields(provider).merging(["nextReset": nextReset.ISO8601Format()]) { _, new in new }
            )
        } catch {
            log.error("warmup sent but verification fetch failed for \(provider.rawValue)")
            DiagnosticLogService.record(
                level: .error,
                category: "usageWarmup",
                action: "verificationFetchFailed",
                fields: providerFields(provider)
            )
        }
    }

    private func providerFields(_ provider: AIProvider) -> [String: String] {
        ["provider": provider.rawValue]
    }

    private func sleep(until date: Date) async {
        await sleep(seconds: max(0, date.timeIntervalSinceNow))
    }

    private func sleep(seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if Task.isCancelled { return }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(min(remaining, 60)))
        }
    }

    static func nextFireDate(
        from snapshot: ProviderUsageSnapshot,
        now: Date,
        resetDelay: TimeInterval,
        lastSentReset: Date?
    ) -> Date? {
        guard let reset = primaryReset(in: snapshot) else { return nil }
        if let lastSentReset, abs(lastSentReset.timeIntervalSince(reset)) < 1 {
            return nil
        }
        return maxDate(now, reset.addingTimeInterval(resetDelay))
    }

    static func primaryReset(in snapshot: ProviderUsageSnapshot) -> Date? {
        snapshot.windows.first { $0.label == "5h" }?.resetsAt
            ?? snapshot.windows.compactMap(\.resetsAt).min()
    }

    private static func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs > rhs ? lhs : rhs
    }
}
