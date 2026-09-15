//
//  SnapSegment.swift
//  Light Stats
//

import Foundation

/// One droppable tile of a layout.
///
/// `title` is a localization key for built-in segments and a literal for user-created ones; the
/// view layer decides which via `SnapLayout.isBuiltIn`. Keeping the model free of `.localized`
/// preserves the Models → (nothing) dependency rule.
struct SnapSegment: Codable, Hashable, Sendable, Identifiable {

    var id: String
    var title: String
    var rect: SnapNormalizedRect
}
