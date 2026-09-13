//
//  AIProvider.swift
//  Light Stats
//

import Foundation

/// Stable id for an AI usage provider. Display names live in Localizable.strings
/// as `aiUsage.<rawValue>` and are resolved by `AIUsageCatalog`.
enum AIProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case deepseek
    case grok
    case zai
    case minimax
    case openrouter
    case warp
    case trae
    case opencodego
    case cursor
    case kimi
    case qoder
    case mimo
}
