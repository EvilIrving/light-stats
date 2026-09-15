//
//  SnapIslandText.swift
//  Light Stats
//

import Foundation

/// Resolves a layout's display name.
///
/// Built-in layouts and their segments store localization keys; anything the user made stores its
/// own text. The resolution lives here rather than on the model so `SnapLayout` stays free of the
/// localization layer, and every view that shows a layout name goes through one place.
enum SnapIslandText {

    static func title(for layout: SnapLayout) -> String {
        layout.isBuiltIn ? layout.title.localized : layout.title
    }

    static func title(for segment: SnapSegment, in layout: SnapLayout) -> String {
        if layout.isBuiltIn { return segment.title.localized }
        if !segment.title.isEmpty { return segment.title }
        let index = layout.segments.firstIndex(where: { $0.id == segment.id }) ?? 0
        return "\(layout.title) · \(index + 1)"
    }

    static func title(for action: WindowSnapAction) -> String {
        action.titleKey.localized
    }

    /// Name of whatever a shortcut is bound to, resolved against the user's own layouts and saved
    /// placements. `nil` means the binding points at geometry that no longer exists.
    static func title(for target: SnapTarget, in configuration: SnapConfiguration) -> String? {
        switch target {
        case .action(let action):
            return title(for: action)
        case .visibility(let command):
            return command.titleKey.localized
        case .region(let rect):
            if let placement = configuration.savedPlacements.first(where: { $0.rect == rect }) {
                return placement.title
            }
            for layout in configuration.allLayouts {
                if let segment = layout.segments.first(where: { $0.rect == rect }) {
                    return title(for: segment, in: layout)
                }
            }
            return nil
        }
    }
}
