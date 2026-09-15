//
//  SnapLayoutDraft.swift
//  Light Stats
//

import Foundation

/// Value-only editing session. An invalid gesture never changes the saved layout.
nonisolated struct SnapLayoutDraft: Equatable {
    var segments: [SnapSegment] = []
    var selectedID: String?
    private var undoStack: [[SnapSegment]] = []

    init(segments: [SnapSegment] = []) {
        self.segments = segments
        selectedID = segments.first?.id
    }

    var selected: SnapSegment? { segments.first { $0.id == selectedID } }
    var canUndo: Bool { !undoStack.isEmpty }

    func accepts(_ rect: SnapNormalizedRect, replacing id: String? = nil) -> Bool {
        guard [rect.x, rect.y, rect.width, rect.height].allSatisfy(\.isFinite),
              rect.width > 0, rect.height > 0,
              rect.minX >= 0, rect.minY >= 0, rect.maxX <= 1, rect.maxY <= 1 else { return false }
        return !segments.contains { segment in
            guard segment.id != id else { return false }
            let other = segment.rect
            return min(rect.maxX, other.maxX) - max(rect.minX, other.minX) > 0.00001
                && min(rect.maxY, other.maxY) - max(rect.minY, other.minY) > 0.00001
        }
    }

    @discardableResult
    mutating func put(_ rect: SnapNormalizedRect, replacing id: String? = nil) -> Bool {
        guard accepts(rect, replacing: id) else { return false }
        if let index = segments.firstIndex(where: { $0.id == id }) {
            guard segments[index].rect != rect else { selectedID = id; return true }
            checkpoint()
            segments[index].rect = rect
            selectedID = id
        } else {
            checkpoint()
            let segment = SnapSegment(id: UUID().uuidString, title: "", rect: rect)
            segments.append(segment)
            selectedID = segment.id
        }
        return true
    }

    mutating func removeSelected() {
        guard let selectedID, segments.contains(where: { $0.id == selectedID }) else { return }
        checkpoint()
        segments.removeAll { $0.id == selectedID }
        self.selectedID = segments.last?.id
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        segments = previous
        selectedID = segments.last?.id
    }

    static func moved(_ rect: SnapNormalizedRect, columns: Int, rows: Int) -> SnapNormalizedRect {
        SnapNormalizedRect(
            x: min(max(rect.x + Double(columns) / 8, 0), 1 - rect.width),
            y: min(max(rect.y + Double(rows) / 8, 0), 1 - rect.height), width: rect.width, height: rect.height
        )
    }

    static func resized(_ rect: SnapNormalizedRect, columns: Int, rows: Int) -> SnapNormalizedRect {
        SnapNormalizedRect(
            x: rect.x, y: rect.y,
            width: min(max(rect.width + Double(columns) / 8, 0.125), 1 - rect.x),
            height: min(max(rect.height + Double(rows) / 8, 0.125), 1 - rect.y)
        )
    }

    private mutating func checkpoint() {
        undoStack.append(segments)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }
}
