//
//  UsageBalance.swift
//  Light Stats
//

import Foundation

/// Prepaid / gift balance. Amounts stay server strings so we never invent precision.
struct UsageBalance: Codable, Equatable, Sendable {
    let currency: String
    let total: String
    let granted: String?
    let toppedUp: String?
    let isAvailable: Bool
}
