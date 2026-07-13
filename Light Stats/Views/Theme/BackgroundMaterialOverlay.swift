//
//  BackgroundMaterialOverlay.swift
//  Light Stats
//

import SwiftUI

/// Composes independent material effects above the single scene canvas.
struct BackgroundMaterialOverlay: View {
    let effects: [AnyBackgroundMaterialEffect]
    let configuration: BackgroundMaterialConfiguration

    var body: some View {
        ZStack {
            ForEach(effects) { effect in
                if effect.isEnabled(configuration: configuration) {
                    effect.makeLayer(configuration: configuration)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
