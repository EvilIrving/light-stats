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
        let halo = BackgroundSceneFrame.RadialLight(
            center: lunarState.haloCenter,
            radius: lunarState.haloRadius,
            innerColor: palette.moonCore,
            outerColor: palette.moonlight,
            intensity: lunarState.haloIntensity,
            softness: min(size.width, size.height) * 0.035,
            blendMode: .screen
        )
        let moonlight = BackgroundSceneFrame.ProjectedLight(
            source: lunarState.source,
            target: lunarState.target,
            sourceWidth: lunarState.sourceWidth,
            targetWidth: lunarState.targetWidth,
            color: palette.moonlight,
            intensity: lunarState.intensity,
            softness: min(size.width, size.height) * 0.055,
            blendMode: .screen
        )
        return BackgroundSceneFrame(primitives: [
            .colorFill(palette.base),
            .radialLight(halo),
            .projectedLight(moonlight)
        ])
    }
}
