//
//  SnapZonePolicy.swift
//  Light Stats
//

import CoreGraphics

struct SnapZoneResult: Sendable, Hashable {
    var zone: SnapZone
    var target: SnapTarget?
    var isIslandActive: Bool
    var screen: SnapScreenGeometry

    static let none = SnapZoneResult(zone: .none, target: nil, isIslandActive: false,
                                     screen: SnapScreenGeometry(frame: .zero, visibleFrame: .zero))
    var isActive: Bool { isIslandActive || zone != .none }
}

nonisolated enum SnapZonePolicy {
    static func result(
        pointer: CGPoint, screen: SnapScreenGeometry, configuration: SnapZoneConfiguration,
        previous: SnapZoneResult? = nil
    ) -> SnapZoneResult {
        let empty = SnapZoneResult(zone: .none, target: nil, isIslandActive: false, screen: screen)
        guard configuration.isActive else { return empty }
        let slack = max(configuration.offscreenTolerance, 0)
        let allowed = CGRect(x: screen.frame.minX - slack, y: screen.visibleFrame.minY - slack,
                             width: screen.frame.width + slack * 2,
                             height: screen.frame.maxY - screen.visibleFrame.minY + slack * 2)
        guard allowed.contains(pointer) else { return empty }
        let regions = SnapEdgeRegionCatalog.regions(screen: screen, configuration: configuration)
        let current = regions.first { $0.frame.contains(pointer) }

        // Corners and the island claim their own areas immediately. Ordinary adjacent bands keep
        // the previous target for six points across their shared boundary, avoiding flicker.
        if let previous, previous.screen == screen, previous.target != nil,
           current?.isIsland != true, !(current?.zone.isCorner == true && !previous.zone.isCorner),
           regions.contains(where: {
               $0.zone == previous.zone && !$0.isIsland
                   && $0.frame.insetBy(dx: -SnapEdgeRegionCatalog.boundaryHysteresis,
                                      dy: -SnapEdgeRegionCatalog.boundaryHysteresis).contains(pointer)
           }) {
            return previous
        }
        guard let current else { return empty }
        return SnapZoneResult(
            zone: current.zone,
            target: current.isIsland ? nil : current.zone.normalizedRect.map { .region($0) },
            isIslandActive: current.isIsland,
            screen: screen
        )
    }
}
