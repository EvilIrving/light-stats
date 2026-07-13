//
//  InkNightSceneModel.swift
//  Light Stats
//

import CoreGraphics
import Foundation

struct InkNightSceneModel: BackgroundSceneModel {
    let palette: InkNightBackgroundTheme.Palette

    func makeFrame(
        time: TimeInterval,
        size: CGSize,
        configuration: BackgroundSceneConfiguration
    ) -> BackgroundSceneFrame {
        let lunarState = InkNightPhysics.lunarState(
            time: time,
            size: size,
            seed: configuration.sceneSeed
        )
        let moonlight = BackgroundSceneFrame.ProjectedLight(
            source: lunarState.source,
            target: lunarState.target,
            sourceWidth: lunarState.sourceWidth,
            targetWidth: lunarState.targetWidth,
            color: palette.moonlight,
            intensity: lunarState.intensity,
            softness: min(size.width, size.height) * 0.085,
            blendMode: .screen
        )
        return BackgroundSceneFrame(primitives: [
            .colorFill(palette.base),
            .projectedLight(moonlight)
        ])
    }
}
