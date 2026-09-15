//
//  SnapLayoutProjection.swift
//  Light Stats
//

import CoreGraphics

/// Projects actual placement rectangles into any preview without changing their proportions or gaps.
nonisolated enum SnapLayoutProjection {
    static let referenceSize = CGSize(width: 1440, height: 900)

    static func viewport(in bounds: CGRect, sourceSize: CGSize) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    static func frame(
        for rect: SnapNormalizedRect,
        in bounds: CGRect,
        margins: SnapMargins,
        sourceSize: CGSize = referenceSize
    ) -> CGRect {
        let viewport = viewport(in: bounds, sourceSize: sourceSize)
        guard viewport.width > 0 else { return .zero }
        let placed = SnapGridGeometry.frame(for: rect, in: CGRect(origin: .zero, size: sourceSize), margins: margins)
        let scale = viewport.width / sourceSize.width
        return CGRect(
            x: viewport.minX + placed.minX * scale, y: viewport.minY + placed.minY * scale,
            width: placed.width * scale, height: placed.height * scale
        )
    }
}
