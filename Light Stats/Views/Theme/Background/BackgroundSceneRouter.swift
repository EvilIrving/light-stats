//
//  BackgroundSceneRouter.swift
//  Light Stats
//

import AppKit
import SwiftUI

struct BackgroundSceneRouter: View {
    let sceneID: BackgroundSceneID
    let appearance: ThemeAppearanceConfiguration
    let cornerRadius: CGFloat
    let configuresWindow: Bool
    let fallbackMaterial: NSVisualEffectView.Material

    @ViewBuilder
    var body: some View {
        switch (sceneID, appearance) {
        case (.systemGlass, _):
            SystemGlassScene(
                cornerRadius: cornerRadius,
                fallbackMaterial: fallbackMaterial,
                configuresWindow: configuresWindow
            )
        case let (.sunGold, .film(configuration)):
            SunGoldScene(input: SunGoldSceneInput(configuration))
        case let (.inkNight, .noir(configuration)):
            InkNightScene(input: InkNightSceneInput(configuration))
        case (.sunGold, _):
            SunGoldScene(input: .defaults)
        case (.inkNight, _):
            InkNightScene(input: .defaults)
        case (.technicalPaper, _):
            TechnicalPaperScene()
        }
    }
}
