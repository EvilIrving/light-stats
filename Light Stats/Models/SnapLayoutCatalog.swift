//
//  SnapLayoutCatalog.swift
//  Light Stats
//

import Foundation

/// The layouts every install starts with.
///
/// Deliberately small and legible. The four arrangement families users ask for (`Halves`,
/// `Thirds`, `Right Stack`, `Quadrants`) plus a regular grid family, because a grid is what the
/// island's tile buttons are actually good at expressing. Anything else the user builds themselves
/// with the grid selector — a better answer than shipping dozens of presets nobody can name.
enum SnapLayoutCatalog {

    static let halvesID = "built-in-halves"
    static let thirdsID = "built-in-thirds"
    static let twoThirdsID = "built-in-two-thirds"
    static let quadrantsID = "built-in-quadrants"
    static let sixthsID = "built-in-sixths"
    static let ninthsID = "built-in-ninths"
    static let rightStackID = "built-in-right-stack"
    static let leftStackID = "built-in-left-stack"

    /// Built-ins in the order the settings list and the island show them.
    static var builtIn: [SnapLayout] {
        [halves, thirds, twoThirds, quadrants, sixths, ninths, rightStack, leftStack]
    }

    static var halves: SnapLayout {
        SnapLayout(
            id: halvesID,
            title: "window.layout.halves",
            isBuiltIn: true,
            segments: [
                segment("left", "window.segment.left", .leftHalf),
                segment("right", "window.segment.right", .rightHalf)
            ]
        )
    }

    static var thirds: SnapLayout {
        SnapLayout(
            id: thirdsID,
            title: "window.layout.thirds",
            isBuiltIn: true,
            segments: [
                segment("first", "window.segment.firstThird", SnapNormalizedRect(columns: 3, rows: 1, column: 0, row: 0)),
                segment("middle", "window.segment.middleThird", SnapNormalizedRect(columns: 3, rows: 1, column: 1, row: 0)),
                segment("last", "window.segment.lastThird", SnapNormalizedRect(columns: 3, rows: 1, column: 2, row: 0))
            ]
        )
    }

    /// "Thirds" is read two ways: three equal columns, or 2/3 + 1/3. Both are kept so both readings
    /// of "thirds" are reachable instead of picking one for the user.
    static var twoThirds: SnapLayout {
        SnapLayout(
            id: twoThirdsID,
            title: "window.layout.twoThirds",
            isBuiltIn: true,
            segments: [
                segment("wide", "window.segment.twoThirds", SnapNormalizedRect(columns: 3, rows: 1, column: 0, row: 0, columnSpan: 2)),
                segment("narrow", "window.segment.oneThird", SnapNormalizedRect(columns: 3, rows: 1, column: 2, row: 0))
            ]
        )
    }

    static var quadrants: SnapLayout {
        SnapLayout(
            id: quadrantsID,
            title: "window.layout.quadrants",
            isBuiltIn: true,
            segments: [
                segment("topLeft", "window.segment.topLeft", .topLeftQuarter),
                segment("topRight", "window.segment.topRight", .topRightQuarter),
                segment("bottomLeft", "window.segment.bottomLeft", .bottomLeftQuarter),
                segment("bottomRight", "window.segment.bottomRight", .bottomRightQuarter)
            ]
        )
    }

    static var sixths: SnapLayout {
        SnapLayout(
            id: sixthsID,
            title: "window.layout.sixths",
            isBuiltIn: true,
            segments: grid(columns: 3, rows: 2)
        )
    }

    static var ninths: SnapLayout {
        SnapLayout(
            id: ninthsID,
            title: "window.layout.ninths",
            isBuiltIn: true,
            segments: grid(columns: 3, rows: 3)
        )
    }

    /// Left half full height plus the right half split — the "Right Stack" preset.
    static var rightStack: SnapLayout {
        SnapLayout(
            id: rightStackID,
            title: "window.layout.rightStack",
            isBuiltIn: true,
            segments: [
                segment("left", "window.segment.left", .leftHalf),
                segment("topRight", "window.segment.topRight", .topRightQuarter),
                segment("bottomRight", "window.segment.bottomRight", .bottomRightQuarter)
            ]
        )
    }

    static var leftStack: SnapLayout {
        SnapLayout(
            id: leftStackID,
            title: "window.layout.leftStack",
            isBuiltIn: true,
            segments: [
                segment("right", "window.segment.right", .rightHalf),
                segment("topLeft", "window.segment.topLeft", .topLeftQuarter),
                segment("bottomLeft", "window.segment.bottomLeft", .bottomLeftQuarter)
            ]
        )
    }

    static func layout(id: String) -> SnapLayout? {
        builtIn.first { $0.id == id }
    }

    // MARK: - Builders

    private static func grid(columns: Int, rows: Int) -> [SnapSegment] {
        var segments: [SnapSegment] = []
        for row in 0..<rows {
            for column in 0..<columns {
                segments.append(
                    SnapSegment(
                        id: "cell-\(column)-\(row)",
                        title: "window.segment.cell",
                        rect: SnapNormalizedRect(
                            columns: columns,
                            rows: rows,
                            column: column,
                            row: row
                        )
                    )
                )
            }
        }
        return segments
    }

    private static func segment(_ id: String, _ title: String, _ rect: SnapNormalizedRect) -> SnapSegment {
        SnapSegment(id: id, title: title, rect: rect)
    }
}
