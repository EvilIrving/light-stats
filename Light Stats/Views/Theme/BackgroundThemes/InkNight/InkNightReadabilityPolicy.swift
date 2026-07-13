//
//  InkNightReadabilityPolicy.swift
//  Light Stats
//

import CoreGraphics

struct InkNightReadabilityPolicy: BackgroundReadabilityPolicy {
    let palette: InkNightBackgroundTheme.Palette

    func makeRegions(
        size: CGSize,
        configuration _: BackgroundSceneConfiguration
    ) -> [BackgroundSceneFrame.Primitive] {
        let insetX = size.width * 0.07
        let insetY = size.height * 0.04
        let region = BackgroundSceneFrame.ReadabilityRegion(
            bounds: CGRect(
                x: insetX,
                y: insetY,
                width: size.width - insetX * 2,
                height: size.height - insetY * 2
            ),
            cornerRadius: min(size.width, size.height) * 0.10,
            color: palette.readingInk,
            opacity: 0.12,
            softness: min(size.width, size.height) * 0.065
        )
        return [.readabilityRegion(region)]
    }
}
