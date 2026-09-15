//
//  SnapNormalizedRect.swift
//  Light Stats
//

import CoreGraphics

/// A rectangle in 0…1 screen space, **top-left origin, `y` growing downward**.
///
/// That is the same orientation Accessibility (`AXPosition`) uses, and the same one the grid
/// selector is drawn in, so a layout is never flipped between the editor, the preview overlay, and
/// the placement engine.
///
/// Wins stores its layouts with a bottom-left (Cocoa) origin — `top-left` carries `y = 0.5` there.
/// Reading that data as-is mirrors the entire layout vertically. This project keeps one convention
/// and states it here so the trap cannot be reintroduced by copying Wins' JSON.
struct SnapNormalizedRect: Codable, Hashable, Sendable {

    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// A rect from grid coordinates: `column`/`row` count from the top-left, spans are in cells.
    init(columns: Int, rows: Int, column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) {
        let safeColumns = max(columns, 1)
        let safeRows = max(rows, 1)
        let column = min(max(column, 0), safeColumns - 1)
        let row = min(max(row, 0), safeRows - 1)
        let columnSpan = min(max(columnSpan, 1), safeColumns - column)
        let rowSpan = min(max(rowSpan, 1), safeRows - row)

        self.x = Double(column) / Double(safeColumns)
        self.y = Double(row) / Double(safeRows)
        self.width = Double(columnSpan) / Double(safeColumns)
        self.height = Double(rowSpan) / Double(safeRows)
    }

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }

    /// Tolerance used when deciding whether a rect edge sits on the screen boundary.
    static let edgeTolerance = 0.0001

    var touchesLeftEdge: Bool { abs(minX) <= Self.edgeTolerance }
    var touchesRightEdge: Bool { abs(maxX - 1) <= Self.edgeTolerance }
    var touchesTopEdge: Bool { abs(minY) <= Self.edgeTolerance }
    var touchesBottomEdge: Bool { abs(maxY - 1) <= Self.edgeTolerance }

    static let full = SnapNormalizedRect(x: 0, y: 0, width: 1, height: 1)

    // The standard tiles. Named so zone detection, the layout catalog, and the tests all agree on
    // one definition instead of recomputing halves and thirds at each call site.
    static let leftHalf = SnapNormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
    static let rightHalf = SnapNormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
    static let topHalf = SnapNormalizedRect(x: 0, y: 0, width: 1, height: 0.5)
    static let bottomHalf = SnapNormalizedRect(x: 0, y: 0.5, width: 1, height: 0.5)
    static let topLeftQuarter = SnapNormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
    static let topRightQuarter = SnapNormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
    static let bottomLeftQuarter = SnapNormalizedRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
    static let bottomRightQuarter = SnapNormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
}
