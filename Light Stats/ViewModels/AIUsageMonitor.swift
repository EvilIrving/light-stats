//
//  AIUsageMonitor.swift
//  Light Stats
//
//  Created on 2026/06/10.
//
//  Logic chain — AI usage refresh lifecycle:
//
//  ┌─ App launch ─────────────────────────────────────────────┐
//  │  start() → reconfigureTimer(fetchNow: false)             │
//  │  Timer armed, NO fetch.  Avoids Keychain prompt at boot. │
//  └──────────────────────────────────────────────────────────┘
//                           │
//  ┌─ Popover opens ──────────────────────────────────────────┐
//  │  AppDelegate.togglePanel() → refreshIfStale()            │
//  │  If last success > 60s ago → refreshAll()                │
//  │  This is the FIRST fetch for each enabled provider.      │
//  └──────────────────────────────────────────────────────────┘
//                           │
//  ┌─ Periodic timer (AppConfig.aiUsageRefreshInterval) ───────┐
//  │  refreshAll() → refresh(provider) for each enabled       │
//  │  Dedup: skips providers already in-flight.               │
//  └──────────────────────────────────────────────────────────┘
//                           │
//  ┌─ Manual retry (user taps ↻ in error card) ──────────────┐
//  │  retry(provider) → resetCredentialCache() → refresh()   │
//  │  Clears cached failure so keychain re-prompts if needed. │
//  └──────────────────────────────────────────────────────────┘
//                           │
//  ┌─ Provider dispatch ──────────────────────────────────────┐
//  │  .claude → ClaudeUsageService.fetch()                    │
//  │  .codex  → CodexUsageService.fetch()                     │
//  │  .gemini → GeminiUsageService.fetch()                    │
//  └──────────────────────────────────────────────────────────┘
//                           │
//  ┌─ Result handling ────────────────────────────────────────┐
//  │  success      → .loaded(snapshot)                        │
//  │  failure      → .error(error), retryable in the card     │
//  └──────────────────────────────────────────────────────────┘
//

import Foundation
import Combine
import os

/// Polls AI subscription usage (Claude Code / Codex / Gemini) on its own timer,
/// fully independent from SystemMonitor's 1-5s refresh cycle.
/// When all provider toggles are off, no timer exists and no requests are made.
@MainActor
final class AIUsageMonitor: ObservableObject {

    static let shared = AIUsageMonitor()

    @Published private(set) var claudeState: ProviderFetchState = .idle
    @Published private(set) var codexState: ProviderFetchState = .idle
    @Published private(set) var geminiState: ProviderFetchState = .idle
    @Published private(set) var refreshingProviders: Set<AIProvider> = []

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var inFlight: Set<AIProvider> = []
    private var lastSuccessAt: [AIProvider: Date] = [:]
    private let settings = SettingsManager.shared
    private let logger = Logger(subsystem: "com.lightstats.app", category: "AIUsageMonitor")

    /// Refresh triggered by popover opening only if data is older than this
    private let popoverStaleThreshold: TimeInterval = 60

    private init() {}

    // MARK: - Lifecycle

    func start() {
        Publishers.CombineLatest4(
            settings.$aiMonitorClaudeEnabled,
            settings.$aiMonitorCodexEnabled,
            settings.$aiMonitorGeminiEnabled,
            settings.$aiUsageRefreshInterval
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            // A settings change (e.g. user just toggled a provider on) is
            // user-initiated, so fetching immediately is expected.
            self?.reconfigureTimer(fetchNow: true)
        }
        .store(in: &cancellables)

        // At launch we only arm the timer — we do NOT fetch eagerly. The first
        // fetch is deferred to the popover opening (refreshIfStale), so the app
        // never triggers a Keychain authorization prompt just by launching.
        reconfigureTimer(fetchNow: false)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when the popover opens: refresh immediately if data is stale,
    /// without hammering the API on rapid open/close.
    func refreshIfStale() {
        let now = Date()
        let needsRefresh = enabledProviders.contains { provider in
            guard let last = lastSuccessAt[provider] else { return true }
            return now.timeIntervalSince(last) > popoverStaleThreshold
        }
        if needsRefresh {
            refreshAll()
        }
    }

    func retry(_ provider: AIProvider) {
        guard enabledProviders.contains(provider) else { return }
        // A manual retry should re-read credentials from scratch — clear any
        // cached failure so e.g. a previously denied Keychain prompt re-appears.
        if provider == .claude {
            ClaudeUsageService.resetCredentialCache()
        }
        refresh(provider)
    }

    // MARK: - Private

    private var enabledProviders: [AIProvider] {
        var providers: [AIProvider] = []
        if settings.aiMonitorClaudeEnabled { providers.append(.claude) }
        if settings.aiMonitorCodexEnabled { providers.append(.codex) }
        if settings.aiMonitorGeminiEnabled { providers.append(.gemini) }
        return providers
    }

    private func reconfigureTimer(fetchNow: Bool) {
        timer?.invalidate()
        timer = nil

        guard !enabledProviders.isEmpty else { return }

        timer = Timer.scheduledTimer(withTimeInterval: AppConfig.aiUsageRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }
        if fetchNow {
            refreshAll()
        }
    }

    private func refreshAll() {
        for provider in enabledProviders {
            refresh(provider)
        }
    }

    private func refresh(_ provider: AIProvider) {
        guard !inFlight.contains(provider) else { return }
        inFlight.insert(provider)
        refreshingProviders.insert(provider)

        Task { [weak self] in
            let result: Result<ProviderUsageSnapshot, AIUsageError>
            do {
                let snapshot: ProviderUsageSnapshot
                switch provider {
                case .claude: snapshot = try await ClaudeUsageService.fetch()
                case .codex: snapshot = try await CodexUsageService.fetch()
                case .gemini: snapshot = try await GeminiUsageService.fetch()
                }
                result = .success(snapshot)
            } catch let error as AIUsageError {
                result = .failure(error)
            } catch {
                result = .failure(.network)
            }

            await MainActor.run { [weak self] in
                self?.handle(result, for: provider)
            }
        }
    }

    private func handle(_ result: Result<ProviderUsageSnapshot, AIUsageError>, for provider: AIProvider) {
        inFlight.remove(provider)
        refreshingProviders.remove(provider)

        let newState: ProviderFetchState
        switch result {
        case .success(let snapshot):
            lastSuccessAt[provider] = snapshot.fetchedAt
            newState = .loaded(snapshot)
        case .failure(let error):
            logger.error("AI usage refresh failed for \(provider.rawValue, privacy: .public): \(error.logDescription, privacy: .public)")
            newState = .error(error)
        }

        setState(newState, for: provider)
    }

    private func state(for provider: AIProvider) -> ProviderFetchState {
        switch provider {
        case .claude: return claudeState
        case .codex: return codexState
        case .gemini: return geminiState
        }
    }

    private func setState(_ state: ProviderFetchState, for provider: AIProvider) {
        switch provider {
        case .claude: claudeState = state
        case .codex: codexState = state
        case .gemini: geminiState = state
        }
    }
}

private extension AIUsageError {
    var logDescription: String {
        switch self {
        case .credentialsMissing: return "credentialsMissing"
        case .tokenExpired: return "tokenExpired"
        case .network: return "network"
        case .decoding: return "decoding"
        case .endpointNotFound: return "endpointNotFound"
        }
    }
}
