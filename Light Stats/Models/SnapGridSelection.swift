//
//  SnapGridSelection.swift
//  Light Stats
//

import Foundation

/// One cell of the layout grid.
struct SnapGridCell: Hashable, Sendable {
    var column: Int
    var row: Int
}

/// A rectangle being dragged out on the layout grid.
///
/// Pure state and pure geometry, so the whole interaction — anchoring, extending, normalising a
/// backwards drag, clearing — is covered by tests instead of by dragging a mouse across a preview.
/// Kept out of the controller on purpose: a state machine that lived alongside a window and its
/// event monitors would not be testable.
struct SnapGridSelection: Equatable, Sendable {

    /// The grid is square and small. 8×8 is the fixed size; anything finer
    /// produces tiles too thin to hit at the sizes a window actually gets.
    static let defaultSize = 8

    var columns: Int
    var rows: Int
    private(set) var anchor: SnapGridCell?
    private(set) var head: SnapGridCell?

    init(columns: Int = SnapGridSelection.defaultSize, rows: Int = SnapGridSelection.defaultSize) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
    }

    var isActive: Bool { anchor != nil && head != nil }

    mutating func begin(at cell: SnapGridCell) {
        let clamped = clamp(cell)
        anchor = clamped
        head = clamped
    }

    mutating func extend(to cell: SnapGridCell) {
        guard anchor != nil else { return }
        head = clamp(cell)
    }

    mutating func clear() {
        anchor = nil
        head = nil
    }

    /// The cells inside the selection, in row-major order.
    var cells: [SnapGridCell] {
        guard let anchor, let head else { return [] }
        let minColumn = min(anchor.column, head.column)
        let maxColumn = max(anchor.column, head.column)
        let minRow = min(anchor.row, head.row)
        let maxRow = max(anchor.row, head.row)

        var result: [SnapGridCell] = []
        for row in minRow...maxRow {
            for column in minColumn...maxColumn {
                result.append(SnapGridCell(column: column, row: row))
            }
        }
        return result
    }

    func contains(_ cell: SnapGridCell) -> Bool {
        cells.contains(cell)
    }

    /// The selection as a normalized rect, top-left origin.
    ///
    /// Derived from the grid coordinates rather than from the drag direction, so a drag that starts
    /// at the bottom-right and ends at the top-left produces the same rectangle as the reverse.
    var rect: SnapNormalizedRect? {
        guard let anchor, let head else { return nil }
        let minColumn = min(anchor.column, head.column)
        let maxColumn = max(anchor.column, head.column)
        let minRow = min(anchor.row, head.row)
        let maxRow = max(anchor.row, head.row)

        return SnapNormalizedRect(
            x: Double(minColumn) / Double(columns),
            y: Double(minRow) / Double(rows),
            width: Double(maxColumn - minColumn + 1) / Double(columns),
            height: Double(maxRow - minRow + 1) / Double(rows)
        )
    }

    /// A layout built from the current selection.
    func makeLayout(id: String, title: String) -> SnapLayout? {
        guard let rect else { return nil }
        return SnapLayout(
            id: id,
            title: title,
            isBuiltIn: false,
            segments: [SnapSegment(id: "\(id)-segment", title: title, rect: rect)]
        )
    }

    private func clamp(_ cell: SnapGridCell) -> SnapGridCell {
        SnapGridCell(
            column: min(max(cell.column, 0), columns - 1),
            row: min(max(cell.row, 0), rows - 1)
        )
    }
}
