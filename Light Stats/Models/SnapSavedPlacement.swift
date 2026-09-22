//
//  SnapSavedPlacement.swift
//  Light Stats
//

import Foundation

/// A region the user kept from the grid selector.
///
/// First-class values, stored alongside layouts and promotable into a full layout.
/// Keeping them first-class means the grid selector has somewhere to
/// put a one-off rectangle that is not worth building a named layout around.
struct SnapSavedPlacement: Codable, Hashable, Sendable, Identifiable {

    var id: String
    var title: String
    var rect: SnapNormalizedRect
    /// Seconds since 1970, so the list can be ordered newest-first without a second field.
    var createdAt: Double

    init(id: String = UUID().uuidString, title: String, rect: SnapNormalizedRect, createdAt: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.title = title
        self.rect = rect
        self.createdAt = createdAt
    }
}
