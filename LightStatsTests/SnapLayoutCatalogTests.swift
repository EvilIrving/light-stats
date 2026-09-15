//
//  SnapLayoutCatalogTests.swift
//  Light Stats Tests
//
//  The layout catalog is data, so the tests are about the data holding together: ids resolve, every
//  tile is inside the screen, a grid really covers the screen, and no preset quietly overlaps
//  itself.
//

import XCTest
@testable import Light_Stats

final class SnapLayoutCatalogTests: XCTestCase {

    func testBuiltInIdentifiersAreUniqueAndResolvable() {
        let layouts = SnapLayoutCatalog.builtIn
        XCTAssertEqual(Set(layouts.map(\.id)).count, layouts.count)
        for layout in layouts {
            XCTAssertEqual(SnapLayoutCatalog.layout(id: layout.id)?.id, layout.id)
            XCTAssertTrue(layout.isBuiltIn)
            XCTAssertTrue(layout.isUsable, layout.id)
        }
    }

    func testEverySegmentIsInsideTheScreenAndNamed() {
        for layout in SnapLayoutCatalog.builtIn {
            let ids = layout.segments.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, layout.id)
            for segment in layout.segments {
                XCTAssertFalse(segment.title.isEmpty, "\(layout.id)/\(segment.id)")
                XCTAssertGreaterThan(segment.rect.width, 0, "\(layout.id)/\(segment.id)")
                XCTAssertGreaterThan(segment.rect.height, 0, "\(layout.id)/\(segment.id)")
                XCTAssertGreaterThanOrEqual(segment.rect.minX, -0.0001, "\(layout.id)/\(segment.id)")
                XCTAssertGreaterThanOrEqual(segment.rect.minY, -0.0001, "\(layout.id)/\(segment.id)")
                XCTAssertLessThanOrEqual(segment.rect.maxX, 1.0001, "\(layout.id)/\(segment.id)")
                XCTAssertLessThanOrEqual(segment.rect.maxY, 1.0001, "\(layout.id)/\(segment.id)")
            }
        }
    }

    /// A preset whose tiles do not fill the screen would leave uncovered strip that no drop can
    /// reach — and the island would show a gap the user cannot explain.
    func testBuiltInLayoutsCoverTheWholeScreenExactlyOnce() {
        for layout in SnapLayoutCatalog.builtIn {
            let area = layout.segments.reduce(0.0) { $0 + $1.rect.width * $1.rect.height }
            XCTAssertEqual(area, 1.0, accuracy: 0.0001, layout.id)
        }
    }

    func testGridLayoutsHaveTheExpectedCellCounts() {
        XCTAssertEqual(SnapLayoutCatalog.sixths.segments.count, 6)
        XCTAssertEqual(SnapLayoutCatalog.ninths.segments.count, 9)
        XCTAssertEqual(SnapLayoutCatalog.quadrants.segments.count, 4)
        XCTAssertEqual(SnapLayoutCatalog.halves.segments.count, 2)
        XCTAssertEqual(SnapLayoutCatalog.thirds.segments.count, 3)
        XCTAssertEqual(SnapLayoutCatalog.rightStack.segments.count, 3)
    }

    func testGridCellsAreEvenlySized() {
        for layout in [SnapLayoutCatalog.sixths, SnapLayoutCatalog.ninths] {
            let widths = Set(layout.segments.map { ($0.rect.width * 1_000).rounded() })
            let heights = Set(layout.segments.map { ($0.rect.height * 1_000).rounded() })
            XCTAssertEqual(widths.count, 1, layout.id)
            XCTAssertEqual(heights.count, 1, layout.id)
        }
    }

    /// Wins stores its layouts with a bottom-left origin, so reading them as-is mirrors everything.
    /// These assertions pin the convention this project uses: top-left origin, `y` downward.
    func testLayoutsAreStoredTopLeftOrigin() {
        let quadrants = SnapLayoutCatalog.quadrants
        let topLeft = quadrants.segments.first { $0.id == "topLeft" }
        let bottomLeft = quadrants.segments.first { $0.id == "bottomLeft" }
        XCTAssertEqual(topLeft?.rect.y, 0)
        XCTAssertEqual(bottomLeft?.rect.y, 0.5)
        XCTAssertLessThan(topLeft?.rect.y ?? 1, bottomLeft?.rect.y ?? 0)
    }

    func testRightStackKeepsTheLeftHalfFullHeight() {
        let left = SnapLayoutCatalog.rightStack.segments.first { $0.id == "left" }
        XCTAssertEqual(left?.rect, .leftHalf)

        let topRight = SnapLayoutCatalog.rightStack.segments.first { $0.id == "topRight" }
        XCTAssertEqual(topRight?.rect, .topRightQuarter)
    }

    // MARK: - Normalized rects

    func testGridCoordinatesBecomeNormalizedRects() {
        let rect = SnapNormalizedRect(columns: 3, rows: 2, column: 2, row: 1)
        XCTAssertEqual(rect.x, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(rect.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.5, accuracy: 0.0001)
    }

    func testGridCoordinatesClampInsteadOfEscaping() {
        let rect = SnapNormalizedRect(columns: 2, rows: 2, column: 5, row: -3, columnSpan: 9, rowSpan: 9)
        XCTAssertEqual(rect.x, 0.5)
        XCTAssertEqual(rect.y, 0)
        XCTAssertEqual(rect.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(rect.maxY, 1, accuracy: 0.0001)
    }

    func testEdgeTouchingIsTolerantOfFloatDrift() {
        XCTAssertTrue(SnapNormalizedRect(x: 0.0000001, y: 0, width: 0.5, height: 1).touchesLeftEdge)
        XCTAssertTrue(SnapNormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1).touchesRightEdge)
        XCTAssertFalse(SnapNormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5).touchesTopEdge)
    }
}

final class SnapGridSelectionTests: XCTestCase {

    func testForwardDragSelectsTheRectangle() throws {
        var selection = SnapGridSelection(columns: 4, rows: 4)
        selection.begin(at: SnapGridCell(column: 1, row: 1))
        selection.extend(to: SnapGridCell(column: 2, row: 2))

        XCTAssertEqual(selection.cells.count, 4)
        let rect = try XCTUnwrap(selection.rect)
        XCTAssertEqual(rect.x, 0.25)
        XCTAssertEqual(rect.y, 0.25)
        XCTAssertEqual(rect.width, 0.5)
        XCTAssertEqual(rect.height, 0.5)
    }

    /// Dragging right-to-left or bottom-to-top has to produce the same rectangle, or half the ways
    /// a person can draw a tile would create something inverted.
    func testBackwardDragProducesTheSameRect() {
        var forward = SnapGridSelection(columns: 4, rows: 4)
        forward.begin(at: SnapGridCell(column: 1, row: 1))
        forward.extend(to: SnapGridCell(column: 2, row: 2))

        var backward = SnapGridSelection(columns: 4, rows: 4)
        backward.begin(at: SnapGridCell(column: 2, row: 2))
        backward.extend(to: SnapGridCell(column: 1, row: 1))

        XCTAssertEqual(forward.rect, backward.rect)
        XCTAssertEqual(Set(forward.cells), Set(backward.cells))
    }

    func testSingleCellSelection() throws {
        var selection = SnapGridSelection(columns: 8, rows: 8)
        selection.begin(at: SnapGridCell(column: 3, row: 5))
        XCTAssertEqual(selection.cells.count, 1)
        let rect = try XCTUnwrap(selection.rect)
        XCTAssertEqual(rect.width, 0.125, accuracy: 0.0001)
        XCTAssertEqual(rect.y, 0.625, accuracy: 0.0001)
    }

    func testSelectionClampsToTheGrid() {
        var selection = SnapGridSelection(columns: 4, rows: 4)
        selection.begin(at: SnapGridCell(column: 99, row: -5))
        XCTAssertEqual(selection.anchor, SnapGridCell(column: 3, row: 0))
    }

    func testExtendBeforeBeginDoesNothing() {
        var selection = SnapGridSelection(columns: 4, rows: 4)
        selection.extend(to: SnapGridCell(column: 1, row: 1))
        XCTAssertFalse(selection.isActive)
        XCTAssertNil(selection.rect)
    }

    func testClearResetsTheSelection() {
        var selection = SnapGridSelection(columns: 4, rows: 4)
        selection.begin(at: SnapGridCell(column: 0, row: 0))
        selection.extend(to: SnapGridCell(column: 1, row: 1))
        selection.clear()
        XCTAssertFalse(selection.isActive)
        XCTAssertTrue(selection.cells.isEmpty)
    }

    func testContainmentMatchesTheCells() {
        var selection = SnapGridSelection(columns: 8, rows: 8)
        selection.begin(at: SnapGridCell(column: 2, row: 2))
        selection.extend(to: SnapGridCell(column: 3, row: 3))
        XCTAssertTrue(selection.contains(SnapGridCell(column: 3, row: 2)))
        XCTAssertFalse(selection.contains(SnapGridCell(column: 4, row: 2)))
    }

    func testLayoutBuiltFromASelectionCarriesTheTitleAndRect() {
        var selection = SnapGridSelection(columns: 8, rows: 8)
        selection.begin(at: SnapGridCell(column: 0, row: 0))
        selection.extend(to: SnapGridCell(column: 3, row: 7))

        let layout = selection.makeLayout(id: "custom-1", title: "Wide")
        XCTAssertEqual(layout?.segments.count, 1)
        XCTAssertEqual(layout?.segments.first?.rect, selection.rect)
        XCTAssertEqual(layout?.isBuiltIn, false)
        XCTAssertEqual(layout?.title, "Wide")
    }
}
