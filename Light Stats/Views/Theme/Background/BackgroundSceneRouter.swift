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
    /// 宿主窗口是否可见。动态场景在隐藏时停摆：隐藏的 hosting view 不会自动暂停 timeline。
    var isVisible: Bool = true

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
            SunGoldScene(input: SunGoldSceneInput(configuration), isVisible: isVisible)
        case let (.bar, .bar(configuration)):
            BarScene(input: BarSceneInput(configuration), isVisible: isVisible)
        case let (.inkNight, .noir(configuration)):
            InkNightScene(input: InkNightSceneInput(configuration), isVisible: isVisible)
        case (.sunGold, _):
            SunGoldScene(input: .defaults, isVisible: isVisible)
        case (.bar, _):
            BarScene(input: .defaults, isVisible: isVisible)
        case (.inkNight, _):
            InkNightScene(input: .defaults, isVisible: isVisible)
        case (.technicalPaper, _):
            TechnicalPaperScene()
        }
    }
}
