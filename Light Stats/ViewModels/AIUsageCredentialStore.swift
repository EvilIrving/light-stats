//
//  AIUsageCredentialStore.swift
//  Light Stats
//

import AppKit
import Combine
import Foundation

@MainActor
final class AIUsageCredentialStore: ObservableObject {
    static let shared = AIUsageCredentialStore()

    @Published private(set) var tokenPresent: Set<AIProvider> = []

    private var presenceGeneration = 0

    private init() {}

    func refreshPresence() async {
        presenceGeneration += 1
        let generation = presenceGeneration
        let ids = AIUsageCatalog.providers
            .filter { $0.credential == .apiToken }
            .map(\.id)
        var next = Set<AIProvider>()
        for id in ids where (try? await KeychainCredentialWriter.loadToken(for: id)) != nil {
            next.insert(id)
        }
        guard generation == presenceGeneration else { return }
        tokenPresent = next
    }

    func save(token: String, for id: AIProvider) async -> Bool {
        let account = KeychainCredentialWriter.account(for: id)
        let ok = await Task.detached(priority: .userInitiated) {
            KeychainCredentialWriter.write(account: account, secret: token)
        }.value
        record(action: ok ? "written" : "writeFailed", id: id)
        if ok {
            tokenPresent.insert(id)
            AIUsageMonitor.shared.credentialsChanged(for: id, hasToken: true)
        }
        await refreshPresence()
        return ok
    }

    func copyToken(for id: AIProvider) async -> Bool {
        let copied = await Task.detached(priority: .userInitiated) { () -> String? in
            try? KeychainCredentialWriter.readToken(for: id)
        }.value
        guard let copied else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(copied, forType: .string)
        record(action: "copied", id: id)
        return true
    }

    func clear(id: AIProvider) async -> Bool {
        let account = KeychainCredentialWriter.account(for: id)
        let ok = await Task.detached(priority: .userInitiated) {
            KeychainCredentialWriter.delete(account: account)
        }.value
        record(action: "cleared", id: id)
        if ok {
            tokenPresent.remove(id)
            AIUsageMonitor.shared.credentialsChanged(for: id, hasToken: false)
        }
        await refreshPresence()
        return ok
    }

    private func record(action: String, id: AIProvider) {
        DiagnosticLogService.record(
            category: "ai.usage.credential",
            action: action,
            fields: ["provider": id.rawValue]
        )
    }
}
