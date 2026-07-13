//
//  GrainBackgroundMaterial.swift
//  Light Stats
//

import SwiftUI

struct GrainBackgroundMaterial: BackgroundMaterialEffect {
    let identifier: String
    let opacity: Double
    let warmth: Double

    func isEnabled(configuration: BackgroundMaterialConfiguration) -> Bool {
        configuration.grainEnabled
    }

    func makeLayer(configuration _: BackgroundMaterialConfiguration) -> some View {
        GrainTextureView(opacity: opacity, warmth: warmth)
    }
}
