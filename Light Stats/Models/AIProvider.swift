//
//  AIProvider.swift
//  Light Stats
//

import Foundation

/// Stable id for an AI usage provider. Display names live in Localizable.strings
/// as `aiUsage.<rawValue>` and are resolved by `AIUsageCatalog`.
enum AIProvider: String, Codable, CaseIterable, Sendable {
    // Quota / window providers first; balance-only providers last (grouped).
    case claude
    case codex
    case gemini
    case grok
    case warp
    case trae
    case opencodego
    case cursor
    case kimi
    case qoder
    case deepseek
    case zai
    case minimax
    case openrouter
    case mimo
}
