//
//  SystemGlassScene.swift
//  Light Stats
//

import AppKit
import SwiftUI

struct SystemGlassScene: View {
    let cornerRadius: CGFloat
    let fallbackMaterial: NSVisualEffectView.Material
    let configuresWindow: Bool

    var body: some View {
        GlassBackgroundView(
            cornerRadius: cornerRadius,
            fallbackMaterial: fallbackMaterial,
            configuresWindow: configuresWindow
        )
    }
}
