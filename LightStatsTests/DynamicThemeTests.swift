//
//  DynamicThemeTests.swift
//  Light Stats Tests
//

import SwiftUI
import XCTest
@testable import Light_Stats

@MainActor
final class DynamicThemeTests: XCTestCase {
    func testThemeDefinitionFixesFiveProductPresets() {
        let glass = ThemeDefinition.definition(for: .glass)
        XCTAssertEqual(glass.layout, .instrument)
        XCTAssertEqual(glass.background, .systemGlass)
        XCTAssertTrue(glass.ui.usesVibrantSurfaces)

        let bento = ThemeDefinition.definition(for: .bento)
        XCTAssertEqual(bento.layout, .bento)
        XCTAssertEqual(bento.background, .systemGlass)
        XCTAssertTrue(bento.ui.usesVibrantSurfaces)

        let film = ThemeDefinition.definition(for: .film)
        XCTAssertEqual(film.layout, .instrument)
        XCTAssertEqual(film.background, .sunGold)
        XCTAssertFalse(film.ui.usesVibrantSurfaces)

        let noir = ThemeDefinition.definition(for: .noir)
        XCTAssertEqual(noir.layout, .instrument)
        XCTAssertEqual(noir.background, .inkNight)

        let dataPaper = ThemeDefinition.definition(for: .dataPaper)
        XCTAssertEqual(dataPaper.layout, .instrument)
        XCTAssertEqual(dataPaper.background, .technicalPaper)
        XCTAssertEqual(dataPaper.ui.preferredColorScheme, .light)
        XCTAssertFalse(dataPaper.ui.usesVibrantSurfaces)
    }

    func testAppearanceMapsToSceneInputsAndSceneConfiguration() {
        let filmAppearance = FilmThemeAppearanceConfiguration(grainEnabled: false, lightFlow: 0.65)
        let sunGold = SunGoldSceneInput(filmAppearance)
        XCTAssertFalse(sunGold.grainEnabled)
        XCTAssertEqual(sunGold.lightFlow, 0.65)
        XCTAssertGreaterThan(SunGoldSceneConfiguration.defaults.grain.opacity, 0)
        XCTAssertGreaterThan(SunGoldSceneConfiguration.defaults.grain.scale, 0)
        XCTAssertTrue(SunGoldSceneConfiguration.defaults.lightField.primaryRibbon.isEnabled)

        let noirAppearance = NoirThemeAppearanceConfiguration(grainEnabled: true, lightFlow: 0.2)
        let inkNight = InkNightSceneInput(noirAppearance)
        XCTAssertTrue(inkNight.grainEnabled)
        XCTAssertEqual(inkNight.lightFlow, 0.2)
        XCTAssertGreaterThan(InkNightSceneConfiguration.defaults.grain.opacity, 0)
        XCTAssertTrue(InkNightSceneConfiguration.defaults.lightField.ambientGlow.isEnabled)
    }

    func testDynamicScenePhasePausesAndAdvances() {
        let anchor: CGFloat = 1.25
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let later = start.addingTimeInterval(2)

        XCTAssertEqual(
            SunGoldScene.phase(
                anchor: anchor,
                anchorDate: start,
                at: later,
                lightFlow: 0,
                configuration: SunGoldSceneConfiguration.defaults.flow
            ),
            anchor
        )
        XCTAssertGreaterThan(
            SunGoldScene.phase(
                anchor: anchor,
                anchorDate: start,
                at: later,
                lightFlow: 0.4,
                configuration: SunGoldSceneConfiguration.defaults.flow
            ),
            anchor
        )
        XCTAssertEqual(
            InkNightScene.phase(
                anchor: anchor,
                anchorDate: start,
                at: later,
                lightFlow: 0.01,
                configuration: InkNightSceneConfiguration.defaults.flow
            ),
            anchor
        )
        XCTAssertGreaterThan(
            InkNightScene.phase(
                anchor: anchor,
                anchorDate: start,
                at: later,
                lightFlow: 1,
                configuration: InkNightSceneConfiguration.defaults.flow
            ),
            anchor
        )
    }

    func testSunGoldAndInkNightUseDarkAppearance() {
        XCTAssertEqual(UITokens.film.preferredColorScheme, .dark)
        XCTAssertEqual(UITokens.noir.preferredColorScheme, .dark)
    }

    func testPersistedThemeIdentifiersRemainStable() {
        XCTAssertEqual(AppTheme.film.rawValue, "film")
        XCTAssertEqual(AppTheme.noir.rawValue, "noir")
        XCTAssertEqual(AppTheme.dataPaper.rawValue, "dataPaper")
        XCTAssertEqual(AppTheme.allCases, [.glass, .bento, .film, .noir, .dataPaper])
    }

    func testUnknownStoredThemeFallsBackToNoir() {
        XCTAssertEqual(AppTheme.resolve(stored: nil), .noir)
        XCTAssertEqual(AppTheme.resolve(stored: "mystery"), .noir)
        XCTAssertEqual(AppTheme.resolve(stored: "aurora"), .noir)
        XCTAssertEqual(AppTheme.resolve(stored: "paper"), .noir)
    }
}
