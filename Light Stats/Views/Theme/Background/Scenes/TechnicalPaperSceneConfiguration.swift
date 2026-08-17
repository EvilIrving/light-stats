//
//  TechnicalPaperSceneConfiguration.swift
//  Light Stats
//

import SwiftUI

struct TechnicalPaperSceneConfiguration {
    let baseColor: Color
    let minorGridColor: Color
    let majorGridColor: Color
    let registrationColor: Color
    let minorGridSpacing: CGFloat
    let majorGridSpacing: CGFloat
    let minorGridOpacity: Double
    let majorGridOpacity: Double
    let registrationOpacity: Double
    let minorLineWidth: CGFloat
    let majorLineWidth: CGFloat
    let registrationLineWidth: CGFloat
    let registrationInset: CGFloat
    let registrationMarkLength: CGFloat
    let showsMinorGrid: Bool
    let showsMajorGrid: Bool
    let showsRegistrationMarks: Bool

    static let defaults = TechnicalPaperSceneConfiguration(
        baseColor: Color(red: 0.957, green: 0.965, blue: 0.973),
        minorGridColor: Color(red: 0.20, green: 0.27, blue: 0.34),
        majorGridColor: Color(red: 0.12, green: 0.18, blue: 0.24),
        registrationColor: Color(red: 0.89, green: 0.23, blue: 0.23),
        minorGridSpacing: 8,
        majorGridSpacing: 32,
        minorGridOpacity: 0.045,
        majorGridOpacity: 0.09,
        registrationOpacity: 0.20,
        minorLineWidth: 0.5,
        majorLineWidth: 0.75,
        registrationLineWidth: 0.75,
        registrationInset: 16,
        registrationMarkLength: 7,
        showsMinorGrid: true,
        showsMajorGrid: true,
        showsRegistrationMarks: true
    )
}
