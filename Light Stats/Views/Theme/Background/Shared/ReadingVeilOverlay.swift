//
//  ReadingVeilOverlay.swift
//  Light Stats
//

import SwiftUI

struct ReadingVeilOverlay: View {
    let configuration: ReadingVeilConfiguration
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let motionOffset: CGPoint

    var body: some View {
        let positionX = 0.5 + Double(motionOffset.x / max(width, 1))
        let positionY = 0.5 + Double(motionOffset.y / max(height, 1))
        let veilX = configuration.centerX
            + (positionX - 0.5) * configuration.horizontalFollow
        let veilY = configuration.centerY
            + (positionY - 0.5) * configuration.verticalFollow

        RadialGradient(
            colors: [
                configuration.centerColor.opacity(configuration.innerOpacity),
                configuration.centerColor.opacity(configuration.middleOpacity),
                configuration.centerColor.opacity(configuration.outerOpacity),
                Color.clear
            ],
            center: UnitPoint(x: veilX, y: veilY),
            startRadius: scale * configuration.startRadiusScale,
            endRadius: max(width, height) * configuration.endRadiusScale
        )
        .allowsHitTesting(false)
    }
}
