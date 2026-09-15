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
    /// 宿主窗口是否可见。动态场景在隐藏时停摆：隐藏的 hosting view 不会自动暂停 timeline。
    var isVisible: Bool = true

    var body: some View {
        BackgroundSceneRouter(
            sceneID: sceneID,
            appearance: appearance,
            cornerRadius: cornerRadius,
            configuresWindow: configuresWindow,
            fallbackMaterial: fallbackMaterial,
            isVisible: isVisible
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}
