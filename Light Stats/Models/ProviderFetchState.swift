//
//  ProviderFetchState.swift
//  Light Stats
//

import Foundation

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
        case .loaded(let snapshot): return snapshot
        case .idle, .error: return nil
        }
    }
}
