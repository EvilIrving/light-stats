//
//  SnapEdgeRegion.swift
//  Light Stats
//

import CoreGraphics

struct SnapEdgeRegion: Sendable {
    var zone: SnapZone
    var frame: CGRect
    var isIsland = false
}
