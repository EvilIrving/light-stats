//
//  SunGoldSceneModel.swift
//  Light Stats
//

import CoreGraphics
import Foundation

struct SunGoldSceneModel: BackgroundSceneModel {
    let palette: SunGoldBackgroundTheme.Palette

    func makeFrame(
        time: TimeInterval,
        size: CGSize,
        configuration: BackgroundSceneConfiguration
    ) -> BackgroundSceneFrame {
        let solarState = SunGoldPhysics.solarState(
            time: time,
            size: size,
            seed: configuration.sceneSeed
        )
        let sun = BackgroundSceneFrame.RadialLight(
            center: solarState.center,
            radius: max(size.width, size.height) * 0.88,
            innerColor: palette.sunCore,
            outerColor: palette.sunEdge,
            intensity: solarState.brightness,
            softness: min(size.width, size.height) * 0.045,
            blendMode: .plusLighter
        )
        return BackgroundSceneFrame(primitives: [
            .colorFill(palette.base),
            .radialLight(sun)
        ])
    }
}
