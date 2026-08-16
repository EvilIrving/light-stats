//
//  DynamicThemeTests.swift
//  Light Stats Tests
//

import SwiftUI
import XCTest
@testable import Light_Stats

@MainActor
final class DynamicThemeTests: XCTestCase {
    func testThemeDefinitionFixesFourProductPresets() {
        let glass = ThemeDefinition.definition(for: .glass)
        XCTAssertEqual(glass.layout, .instrument)
        XCTAssertEqual(glass.background.kind, .glass)
        XCTAssertTrue(glass.ui.usesVibrantSurfaces)
        XCTAssertFalse(glass.ui.usesBentoLayout)

        let bento = ThemeDefinition.definition(for: .bento)
        XCTAssertEqual(bento.layout, .bento)
        XCTAssertEqual(bento.background.kind, .glass)
        XCTAssertTrue(bento.ui.usesBentoLayout)
        XCTAssertTrue(bento.ui.usesVibrantSurfaces)

        let film = ThemeDefinition.definition(for: .film)
        XCTAssertEqual(film.layout, .instrument)
        XCTAssertEqual(film.background.kind, .mesh)
        XCTAssertEqual(film.background.meshRenderer, .film)
        XCTAssertFalse(film.ui.usesVibrantSurfaces)

        let noir = ThemeDefinition.definition(for: .noir)
        XCTAssertEqual(noir.layout, .instrument)
        XCTAssertEqual(noir.background.kind, .mesh)
        XCTAssertEqual(noir.background.meshRenderer, .noir)
        XCTAssertFalse(noir.ui.usesBentoLayout)
    }

    func testMeshBackgroundsShareGrainStrength() {
        XCTAssertGreaterThan(BackgroundConfiguration.film.grainOpacity, 0)
        XCTAssertEqual(
            BackgroundConfiguration.film.grainOpacity,
            BackgroundConfiguration.noir.grainOpacity
        )
    }

    func testSunGoldAndInkNightUseDarkAppearance() {
        XCTAssertEqual(UITokens.film.preferredColorScheme, .dark)
        XCTAssertEqual(UITokens.noir.preferredColorScheme, .dark)
    }

    func testGlassBackgroundsHaveNoMeshRenderer() {
        XCTAssertNil(BackgroundConfiguration.glass.meshRenderer)
        XCTAssertEqual(BackgroundConfiguration.glass.grainOpacity, 0)
    }

    func testPersistedThemeIdentifiersRemainStable() {
        XCTAssertEqual(AppTheme.film.rawValue, "film")
        XCTAssertEqual(AppTheme.noir.rawValue, "noir")
        XCTAssertEqual(AppTheme.allCases, [.glass, .bento, .film, .noir])
    }

    func testUnknownStoredThemeFallsBackToNoir() {
        XCTAssertEqual(AppTheme.resolve(stored: nil), .noir)
        XCTAssertEqual(AppTheme.resolve(stored: "mystery"), .noir)
        XCTAssertEqual(AppTheme.resolve(stored: "aurora"), .noir)
        XCTAssertEqual(AppTheme.resolve(stored: "paper"), .noir)
    }
}
