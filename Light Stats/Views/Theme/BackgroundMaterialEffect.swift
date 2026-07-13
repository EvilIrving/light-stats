//
//  BackgroundMaterialEffect.swift
//  Light Stats
//

import SwiftUI

protocol BackgroundMaterialEffect {
    associatedtype Content: View

    var identifier: String { get }

    func isEnabled(configuration: BackgroundMaterialConfiguration) -> Bool

    @ViewBuilder
    func makeLayer(configuration: BackgroundMaterialConfiguration) -> Content
}

extension BackgroundMaterialEffect {
    func isEnabled(configuration _: BackgroundMaterialConfiguration) -> Bool {
        true
    }
}
