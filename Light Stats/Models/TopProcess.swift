//
//  ProcessStats.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import Foundation

// MARK: - Top Process Info

/// Represents a process with CPU/memory usage
nonisolated struct TopProcess: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let cpuPercent: Double
    let memPercent: Double

    /// Format CPU percentage for display
    var cpuDisplayString: String {
        String(format: "%.1f%%", cpuPercent)
    }
}
