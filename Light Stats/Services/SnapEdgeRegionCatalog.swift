//
//  SnapEdgeRegionCatalog.swift
//  Light Stats
//

import CoreGraphics

/// Position bands, in priority order. Preview, release and the Settings desktop read this same table.
nonisolated enum SnapEdgeRegionCatalog {
    static let boundaryHysteresis: CGFloat = 6

    static func regions(screen: SnapScreenGeometry, configuration: SnapZoneConfiguration) -> [SnapEdgeRegion] {
        guard configuration.isActive, screen.frame.width > 0, screen.frame.height > 0 else { return [] }
        let bounds = screen.frame
        let top = screen.visibleFrame.minY
        let height = max(bounds.maxY - top, 1)
        let threshold = max(configuration.edgeThreshold, 0)
        let slack = max(configuration.offscreenTolerance, 0)
        let corner = min(max(height * 0.04, threshold), 48, max(bounds.width * configuration.cornerWidthRatio, 0))
        var result: [SnapEdgeRegion] = []

        if configuration.cornersEnabled {
            result += [
                SnapEdgeRegion(zone: .topLeft, frame: CGRect(x: bounds.minX - slack, y: top - slack,
                                                            width: corner + slack, height: corner + slack)),
                SnapEdgeRegion(zone: .topRight, frame: CGRect(x: bounds.maxX - corner, y: top - slack,
                                                             width: corner + slack, height: corner + slack)),
                SnapEdgeRegion(zone: .bottomLeft, frame: CGRect(x: bounds.minX - slack, y: bounds.maxY - corner,
                                                               width: corner + slack, height: corner + slack)),
                SnapEdgeRegion(zone: .bottomRight, frame: CGRect(x: bounds.maxX - corner, y: bounds.maxY - corner,
                                                                width: corner + slack, height: corner + slack))
            ]
        }
        if configuration.topEdgeMode == .island {
            let width = bounds.width * min(max(configuration.islandCenterWidthRatio, 0.1), 1)
            result.append(SnapEdgeRegion(zone: .top, frame: CGRect(x: bounds.midX - width / 2, y: top - slack,
                                                                  width: width, height: threshold + slack), isIsland: true))
        }
        if configuration.topEdgeMode != .disabled {
            result.append(SnapEdgeRegion(zone: .top, frame: CGRect(x: bounds.minX - slack, y: top - slack,
                                                                  width: bounds.width + slack * 2, height: threshold + slack)))
        }
        guard configuration.edgesEnabled else { return result }

        // Moving down either side offers horizontal halves around its central vertical half.
        let sideBands: [(CGFloat, CGFloat, SnapZone, SnapZone)] = [
            (0, 0.18, .upperHalf, .upperHalf),
            (0.18, 0.82, .left, .right),
            (0.82, 1, .lowerHalf, .lowerHalf)
        ]
        for (start, end, left, right) in sideBands {
            let y = top + start * height
            let bandHeight = (end - start) * height
            result.append(SnapEdgeRegion(zone: left, frame: CGRect(x: bounds.minX - slack, y: y,
                                                                  width: threshold + slack, height: bandHeight)))
            result.append(SnapEdgeRegion(zone: right, frame: CGRect(x: bounds.maxX - threshold, y: y,
                                                                   width: threshold + slack, height: bandHeight)))
        }

        // Five destinations across the bottom: 1/3, 2/3, centred 1/3, 2/3, 1/3.
        let bottomZones: [SnapZone] = [.leftThird, .leftTwoThirds, .centerThird, .rightTwoThirds, .rightThird]
        for (index, zone) in bottomZones.enumerated() {
            result.append(SnapEdgeRegion(zone: zone, frame: CGRect(
                x: bounds.minX + CGFloat(index) * bounds.width / 5, y: bounds.maxY - threshold,
                width: bounds.width / 5, height: threshold + slack
            )))
        }
        return result
    }
}
