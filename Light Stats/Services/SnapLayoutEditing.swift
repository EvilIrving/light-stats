//
//  SnapLayoutEditing.swift
//  Light Stats
//

import Foundation

nonisolated enum SnapLayoutEditing {
    static func save(_ layout: SnapLayout, in configuration: inout SnapConfiguration) {
        guard !layout.isBuiltIn, !layout.segments.isEmpty else { return }
        var validator = SnapLayoutDraft()
        for segment in layout.segments {
            guard validator.put(segment.rect) else { return }
        }
        if let index = configuration.customLayouts.firstIndex(where: { $0.id == layout.id }) {
            configuration.customLayouts[index] = layout
        } else {
            configuration.customLayouts.append(layout)
            configuration.islandLayoutIDs.append(layout.id)
        }
        configuration.pruneDanglingReferences()
    }

    static func savePosition(_ rect: SnapNormalizedRect, title: String, in configuration: inout SnapConfiguration) {
        guard SnapLayoutDraft().accepts(rect), !configuration.savedPlacements.contains(where: { $0.rect == rect }) else { return }
        configuration.savedPlacements.append(SnapSavedPlacement(title: title, rect: rect))
    }

    static func removeLayout(_ id: String, in configuration: inout SnapConfiguration) {
        configuration.customLayouts.removeAll { $0.id == id }
        configuration.islandLayoutIDs.removeAll { $0 == id }
        configuration.pruneDanglingReferences()
    }

    static func removePosition(_ id: String, in configuration: inout SnapConfiguration) {
        configuration.savedPlacements.removeAll { $0.id == id }
        configuration.pruneDanglingReferences()
    }

    static func move(_ id: String, before target: String, in configuration: inout SnapConfiguration) {
        guard id != target, configuration.islandLayoutIDs.contains(id), configuration.islandLayoutIDs.contains(target) else { return }
        configuration.islandLayoutIDs.removeAll { $0 == id }
        guard let index = configuration.islandLayoutIDs.firstIndex(of: target) else { return }
        configuration.islandLayoutIDs.insert(id, at: index)
    }
}
