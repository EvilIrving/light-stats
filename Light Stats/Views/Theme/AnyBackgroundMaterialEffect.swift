//
//  AnyBackgroundMaterialEffect.swift
//  Light Stats
//

import SwiftUI

struct AnyBackgroundMaterialEffect: Identifiable {
    let id: String

    private let isEnabledClosure: (BackgroundMaterialConfiguration) -> Bool
    private let makeLayerClosure: (BackgroundMaterialConfiguration) -> AnyView

    init<Effect: BackgroundMaterialEffect>(_ effect: Effect) {
        id = effect.identifier
        isEnabledClosure = effect.isEnabled
        makeLayerClosure = { configuration in
            AnyView(effect.makeLayer(configuration: configuration))
        }
    }

    func isEnabled(configuration: BackgroundMaterialConfiguration) -> Bool {
        isEnabledClosure(configuration)
    }

    func makeLayer(configuration: BackgroundMaterialConfiguration) -> AnyView {
        makeLayerClosure(configuration)
    }
}
