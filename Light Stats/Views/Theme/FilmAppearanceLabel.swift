//
//  FilmAppearanceLabel.swift
//  Light Stats
//

import SwiftUI

enum FilmAppearanceLabel {
    static let flowValues = [0.0, 0.2, 0.4, 0.65, 1.0]
    static let positionValues = [0.0, 0.25, 0.5, 0.75, 1.0]

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
        case ..<0.25: return "settings.theme.film.flow.gentle".localized
        case ..<0.5: return "settings.theme.film.flow.natural".localized
        case ..<0.75: return "settings.theme.film.flow.smooth".localized
        default: return "settings.theme.film.flow.lively".localized
        }
    }

    static func horizontalPosition(_ value: Double) -> String {
        switch value {
        case ..<0.15: return "settings.theme.film.position.farLeft".localized
        case ..<0.4: return "settings.theme.film.position.left".localized
        case ..<0.6: return "settings.theme.film.position.center".localized
        case ..<0.85: return "settings.theme.film.position.right".localized
        default: return "settings.theme.film.position.farRight".localized
        }
    }

    static func verticalPosition(_ value: Double) -> String {
        switch value {
        case ..<0.15: return "settings.theme.film.position.top".localized
        case ..<0.4: return "settings.theme.film.position.upper".localized
        case ..<0.6: return "settings.theme.film.position.center".localized
        case ..<0.85: return "settings.theme.film.position.lower".localized
        default: return "settings.theme.film.position.bottom".localized
        }
    }
}
