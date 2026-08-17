//
//  FilmAppearanceLabel.swift
//  Light Stats
//

import SwiftUI

enum FilmAppearanceLabel {
    static func discreteBinding(_ source: Binding<Double>, options: [Double]) -> Binding<Double> {
        Binding(
            get: {
                options.min(by: { abs($0 - source.wrappedValue) < abs($1 - source.wrappedValue) })
                    ?? source.wrappedValue
            },
            set: { source.wrappedValue = $0 }
        )
    }

    static func flow(_ value: Double) -> String {
        switch value {
        case ..<0.02: return "settings.theme.film.flow.paused".localized
        case ..<0.7: return "settings.theme.film.flow.natural".localized
        default: return "settings.theme.film.flow.lively".localized
        }
    }
}
