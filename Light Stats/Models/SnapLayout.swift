//
//  SnapLayout.swift
//  Light Stats
//

import Foundation

/// A named arrangement of drop targets.
///
/// Layouts are **data**, not code. A class per arrangement is exactly the shape this refuses;
/// the geometry is stored as normalized rects and every arrangement is solved by a single
/// `SnapGridGeometry` function, so a new preset is a value — and a new test — rather than a class.
struct SnapLayout: Codable, Hashable, Sendable, Identifiable {

    var id: String
    var title: String
    var isBuiltIn: Bool
    var segments: [SnapSegment]

    init(id: String, title: String, isBuiltIn: Bool, segments: [SnapSegment]) {
        self.id = id
        self.title = title
        self.isBuiltIn = isBuiltIn
        self.segments = segments
    }

    /// Whether this layout is safe to hand to the editor. A layout with no tile can never be
    /// dropped on and would leave the island showing an empty panel.
    var isUsable: Bool { !segments.isEmpty }

    func segment(id: String) -> SnapSegment? {
        segments.first { $0.id == id }
    }
}
