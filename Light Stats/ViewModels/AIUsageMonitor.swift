//
//  AIUsageMonitor.swift
//  Light Stats
//
//  Created on 2026/06/10.
//

import Foundation
import Combine

/// Polls AI subscription usage (Claude Code / Codex) on its own timer,
/// fully independent from SystemMonitor's 1-5s refresh cycle.
/// When both provider toggles are off, no timer exists and no requests are made.
@MainActor
final class AIUsageMonitor: ObservableObject {

    static let shared = AIUsageMonitor()

    @Published private(set) var claudeState: ProviderFetchState = .idle
    @Published private(set) var codexState: ProviderFetchState = .idle

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var inFlight: Set<AIProvider> = []
    private var lastSuccessAt: [AIProvider: Date] = [:]
    private let settings = SettingsManager.shared

    /// Refresh triggered by popover opening only if data is older than this
    private let popoverStaleThreshold: TimeInterval = 60

    private init() {
        restoreCachedSnapshots()
    }

    // MARK: - Lifecycle

    func start() {
        Publishers.CombineLatest3(
            settings.$aiMonitorClaudeEnabled,
            settings.$aiMonitorCodexEnabled,
            settings.$aiUsageRefreshInterval
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.reconfigureTimer()
        }
        .store(in: &cancellables)

        reconfigureTimer()
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

    // MARK: - Private

    private var enabledProviders: [AIProvider] {
        var providers: [AIProvider] = []
        if settings.aiMonitorClaudeEnabled { providers.append(.claude) }
        if settings.aiMonitorCodexEnabled { providers.append(.codex) }
        return providers
    }

    private func reconfigureTimer() {
        timer?.invalidate()
        timer = nil

        guard !enabledProviders.isEmpty else { return }

        let interval = settings.aiUsageRefreshInterval.interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }
        refreshAll()
    }

    private func refreshAll() {
        for provider in enabledProviders {
            refresh(provider)
        }
    }

    private func refresh(_ provider: AIProvider) {
        guard !inFlight.contains(provider) else { return }
        inFlight.insert(provider)

        Task { [weak self] in
            let result: Result<ProviderUsageSnapshot, AIUsageError>
            do {
                let snapshot: ProviderUsageSnapshot
                switch provider {
                case .claude: snapshot = try await ClaudeUsageService.fetch()
                case .codex: snapshot = try await CodexUsageService.fetch()
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

        let newState: ProviderFetchState
        switch result {
        case .success(let snapshot):
            lastSuccessAt[provider] = snapshot.fetchedAt
            cacheSnapshot(snapshot)
            newState = .loaded(snapshot)
        case .failure(let error):
            // Keep last good data visible for transient failures;
            // credential problems need the user's attention.
            switch error {
            case .network, .decoding:
                if let previous = state(for: provider).snapshot {
                    newState = .stale(previous)
                } else {
                    newState = .error(error)
                }
            case .tokenExpired, .credentialsMissing:
                newState = .error(error)
            }
        }

        setState(newState, for: provider)
    }

    private func state(for provider: AIProvider) -> ProviderFetchState {
        switch provider {
        case .claude: return claudeState
        case .codex: return codexState
        }
    }

    private func setState(_ state: ProviderFetchState, for provider: AIProvider) {
        switch provider {
        case .claude: claudeState = state
        case .codex: codexState = state
        }
    }

    // MARK: - Snapshot cache (show last data on launch while first fetch runs)

    private func cacheKey(for provider: AIProvider) -> String {
        "aiUsage.snapshot.\(provider.rawValue)"
    }

    private func cacheSnapshot(_ snapshot: ProviderUsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: snapshot.provider))
    }

    private func restoreCachedSnapshots() {
        for provider in AIProvider.allCases {
            guard let data = UserDefaults.standard.data(forKey: cacheKey(for: provider)),
                  let snapshot = try? JSONDecoder().decode(ProviderUsageSnapshot.self, from: data) else {
                continue
            }
            setState(.stale(snapshot), for: provider)
        }
    }
}
