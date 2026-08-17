//
//  BackgroundHost.swift
//  Light Stats
//

import AppKit
import SwiftUI

struct BackgroundHost: View {
    let sceneID: BackgroundSceneID
    let appearance: ThemeAppearanceConfiguration
    var cornerRadius: CGFloat = 12
    var configuresWindow: Bool = false
    var fallbackMaterial: NSVisualEffectView.Material = .sidebar

    var body: some View {
        BackgroundSceneRouter(
            sceneID: sceneID,
            appearance: appearance,
            cornerRadius: cornerRadius,
            configuresWindow: configuresWindow,
            fallbackMaterial: fallbackMaterial
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}
