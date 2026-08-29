//
//  AIUsageInfo.swift
//  Light Stats
//
//  Created on 2026/06/10.
//

import Foundation

/// AI subscription usage providers
enum AIProvider: String, Codable, CaseIterable {
    case claude
    case codex
    case gemini

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "ChatGPT"
        case .gemini: return "Gemini"
        }
    }
}

/// A single rate-limit window (e.g. 5h or weekly)
struct UsageWindow: Codable, Equatable {
    let label: String          // "5h" / "7d" style short label
    let usedPercent: Double    // 0–100
    let resetsAt: Date?
}

/// One successful fetch result for a provider
struct ProviderUsageSnapshot: Codable, Equatable {
    let provider: AIProvider
    let windows: [UsageWindow]
    let fetchedAt: Date
}

enum AIUsageError: Error, Equatable {
    case credentialsMissing
    case tokenExpired
    case network
    case decoding
    /// OAuth usage endpoint returned 404 — endpoint may have moved or been disabled.
    case endpointNotFound
}

/// Per-provider fetch state published to the UI.
/// No `stale` case: the app never shows last-session data. A failed refresh
/// becomes `.error`, so the user sees fresh data, a fetching placeholder, or
/// an explicit retryable error — never an old snapshot.
enum ProviderFetchState: Equatable {
    case idle
    case loaded(ProviderUsageSnapshot)
    case error(AIUsageError)

    var snapshot: ProviderUsageSnapshot? {
        switch self {
        case .loaded(let s): return s
        case .idle, .error: return nil
        }
    }
}
