//
//  FilmVignetteBackgroundMaterial.swift
//  Light Stats
//

import SwiftUI

struct FilmVignetteBackgroundMaterial: BackgroundMaterialEffect {
    let identifier: String
    let tint: BackgroundSceneFrame.Color
    let opacity: Double

    func makeLayer(configuration _: BackgroundMaterialConfiguration) -> some View {
        RadialGradient(
            colors: [
                Color.clear,
                swiftUIColor.opacity(opacity * 0.28),
                swiftUIColor.opacity(opacity)
            ],
            center: .center,
            startRadius: 80,
            endRadius: 520
        )
        .blendMode(.softLight)
    }

    private var swiftUIColor: Color {
        Color(
            red: tint.red,
            green: tint.green,
            blue: tint.blue,
            opacity: tint.opacity
        )
    }
}
