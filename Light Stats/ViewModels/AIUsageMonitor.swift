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
//  ┌─ Manual retry ───────────────────────────────────────────┐
//  │  retry(provider) → resetCredentialCache() → refresh()    │
//  └──────────────────────────────────────────────────────────┘
//                           │
//  ┌─ Provider dispatch ──────────────────────────────────────┐
//  │  UsageProviderRegistry.fetch(id)                         │
//  └──────────────────────────────────────────────────────────┘
//

import Foundation
import Combine
import os

/// Polls AI subscription usage on its own timer, independent from SystemMonitor.
/// When all provider toggles are off, no timer exists and no requests are made.
@MainActor
final class AIUsageMonitor: ObservableObject {

    static let shared = AIUsageMonitor()

    @Published private(set) var states: [AIProvider: ProviderFetchState] = [:]
    @Published private(set) var refreshingProviders: Set<AIProvider> = []

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var requestIDs: [AIProvider: UUID] = [:]
    private var inFlight: Set<AIProvider> = []
    private var lastSuccessAt: [AIProvider: Date] = [:]
    private let settings = SettingsManager.shared

    /// Refresh triggered by popover opening only if data is older than this
    private let popoverStaleThreshold: TimeInterval = 60

    private init() {}

    // MARK: - Lifecycle

    func start() {
        // A settings change (user just toggled a provider on) is user-initiated,
        // so fetching immediately is expected.
        settings.$enabledAIProviders
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconfigureTimer(fetchNow: true)
            }
            .store(in: &cancellables)

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
        UsageProviderRegistry.resetCredentialCache(provider)
        refresh(provider)
    }

    func credentialsChanged(for provider: AIProvider, hasToken: Bool) {
        requestIDs[provider] = nil
        inFlight.remove(provider)
        refreshingProviders.remove(provider)
        lastSuccessAt[provider] = nil
        UsageProviderRegistry.resetCredentialCache(provider)
        setState(hasToken ? .idle : .error(.credentialsMissing), for: provider)
        if hasToken, enabledProviders.contains(provider) {
            refresh(provider)
        }
    }

    func state(for provider: AIProvider) -> ProviderFetchState {
        states[provider] ?? .idle
    }

    // MARK: - Private

    private var enabledProviders: [AIProvider] {
        AIUsageCatalog.providers.map(\.id).filter { settings.isAIProviderEnabled($0) }
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
        let requestID = UUID()
        requestIDs[provider] = requestID
        var nextRefreshing = refreshingProviders
        nextRefreshing.insert(provider)
        refreshingProviders = nextRefreshing

        Task { [weak self] in
            let result: Result<ProviderUsageSnapshot, AIUsageError>
            do {
                let snapshot = try await UsageProviderRegistry.fetch(provider)
                result = .success(snapshot)
            } catch let error as AIUsageError {
                result = .failure(error)
            } catch {
                result = .failure(.network)
            }

            await MainActor.run { [weak self] in
                guard let self, self.requestIDs[provider] == requestID else { return }
                self.requestIDs[provider] = nil
                self.handle(result, for: provider)
            }
        }
    }

    private func handle(_ result: Result<ProviderUsageSnapshot, AIUsageError>, for provider: AIProvider) {
        inFlight.remove(provider)
        var nextRefreshing = refreshingProviders
        nextRefreshing.remove(provider)
        refreshingProviders = nextRefreshing

        let newState: ProviderFetchState
        switch result {
        case .success(let snapshot):
            lastSuccessAt[provider] = snapshot.fetchedAt
            let windows = snapshot.windows.map {
                "\($0.label)|usedPercent=\($0.usedPercent)|resetsAt=\($0.resetsAt?.timeIntervalSince1970.description ?? "unavailable")"
            }.joined(separator: ";")
            DiagnosticLogService.recordSample(
                category: "ai.usage",
                action: "collected",
                fields: ["provider": .privateValue(provider.rawValue), "windows": .privateValue(windows)]
            )
            var probeFields: [String: DiagnosticLogService.Field] = [
                "windowCount": .privateValue(.integer(Int64(snapshot.windows.count)))
            ]
            if let balance = snapshot.balance {
                probeFields["currency"] = .privateValue(balance.currency)
                probeFields["total"] = .privateValue(balance.total)
            }
            DiagnosticLogService.recordProbe(
                component: "AIUsageMonitor",
                operation: "providerUsage",
                identity: provider.rawValue,
                status: .success,
                reasonCode: "snapshotLoaded",
                source: provider.rawValue,
                fields: probeFields
            )
            newState = .loaded(snapshot)
        case .failure(let error):
            DiagnosticLogService.recordProbe(
                component: "AIUsageMonitor",
                operation: "providerUsage",
                identity: provider.rawValue,
                status: .unavailable,
                reasonCode: error.logDescription,
                source: provider.rawValue
            )
            newState = .error(error)
        }

        setState(newState, for: provider)
    }

    private func setState(_ state: ProviderFetchState, for provider: AIProvider) {
        var next = states
        next[provider] = state
        states = next
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
