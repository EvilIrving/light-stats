//
//  DynamicThemeTests.swift
//  Light Stats Tests
//

import SwiftUI
import XCTest
@testable import Light_Stats

@MainActor
final class DynamicThemeTests: XCTestCase {
    func testThemeDefinitionFixesProductPresets() {
        let glass = ThemeDefinition.definition(for: .glass)
        XCTAssertEqual(glass.layout, .instrument)
        XCTAssertEqual(glass.background, .systemGlass)
        XCTAssertTrue(glass.ui.usesVibrantSurfaces)

        let film = ThemeDefinition.definition(for: .film)
        XCTAssertEqual(film.layout, .instrument)
        XCTAssertEqual(film.background, .sunGold)
        XCTAssertEqual(film.ui.chromeStyle, .neon)
        XCTAssertFalse(film.ui.usesVibrantSurfaces)

        let bar = ThemeDefinition.definition(for: .bar)
        XCTAssertEqual(bar.layout, .instrument)
        XCTAssertEqual(bar.background, .bar)
        XCTAssertEqual(bar.ui.preferredColorScheme, .dark)
        XCTAssertEqual(bar.ui.chromeStyle, .nightBar)
        XCTAssertFalse(bar.ui.usesVibrantSurfaces)

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

        let barAppearance = BarThemeAppearanceConfiguration(grainEnabled: false, lightFlow: 0.8)
        let bar = BarSceneInput(barAppearance)
        XCTAssertFalse(bar.grainEnabled)
        XCTAssertEqual(bar.lightFlow, 0.8)
        XCTAssertGreaterThan(BarSceneConfiguration.defaults.grain.opacity, 0)
        XCTAssertTrue(BarSceneConfiguration.defaults.lightField.warmTube.isEnabled)
        XCTAssertTrue(BarSceneConfiguration.defaults.lightField.coolTube.isEnabled)

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
            BarScene.phase(
                anchor: anchor,
                anchorDate: start,
                at: later,
                lightFlow: 0,
                configuration: BarSceneConfiguration.defaults.flow
            ),
            anchor
        )
        XCTAssertGreaterThan(
            BarScene.phase(
                anchor: anchor,
                anchorDate: start,
                at: later,
                lightFlow: 1,
                configuration: BarSceneConfiguration.defaults.flow
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

    func testCustomChromeThemesKeepSharedInstrumentLayout() {
        XCTAssertEqual(ThemeDefinition.definition(for: .film).layout, .instrument)
        XCTAssertEqual(ThemeDefinition.definition(for: .bar).layout, .instrument)
    }

    func testDynamicAndPhotoThemesUseDarkAppearance() {
        XCTAssertEqual(UITokens.film.preferredColorScheme, .dark)
        XCTAssertEqual(UITokens.bar.preferredColorScheme, .dark)
        XCTAssertEqual(UITokens.noir.preferredColorScheme, .dark)
    }

    func testNeonTokensStayDistinctFromNightBar() {
        let neon = UITokens.film
        let bar = UITokens.bar
        XCTAssertNotEqual(neon.accent, bar.accent)
        XCTAssertNotEqual(neon.signalGood, bar.signalGood)
        XCTAssertNotEqual(neon.signalInfo, bar.signalInfo)
        XCTAssertNotEqual(neon.signalAccent, bar.signalAccent)
        XCTAssertNotEqual(neon.signalBad, bar.signalBad)
        XCTAssertNotEqual(neon.signalWarn, bar.signalWarn)
        XCTAssertNotEqual(neon.rowHoverFill, bar.rowHoverFill)
    }

    func testNeonHasNoContentPlate() {
        XCTAssertEqual(UITokens.film.surfaceFill, .clear)
        XCTAssertEqual(UITokens.film.surfaceShadowOpacity, 0)
    }

    func testNeonSeparatesInkIconsChartsAndStatusPaint() {
        let neon = UITokens.film
        XCTAssertNotEqual(neon.metricIcon, neon.inkSecondary)
        XCTAssertNotEqual(neon.chartLine, neon.metricIcon)
        XCTAssertNotEqual(neon.chartSecondary, neon.chartLine)
        XCTAssertNotEqual(neon.signalGood, neon.chartLine)
        XCTAssertNotEqual(neon.signalWarn, neon.signalAccent)
        XCTAssertNotEqual(neon.signalBad, neon.signalAccent)
    }

    func testPersistedThemeIdentifiersRemainStable() {
        XCTAssertEqual(AppTheme.film.rawValue, "film")
        XCTAssertEqual(AppTheme.bar.rawValue, "bar")
        XCTAssertEqual(AppTheme.noir.rawValue, "noir")
        XCTAssertEqual(AppTheme.dataPaper.rawValue, "dataPaper")
        XCTAssertEqual(AppTheme.allCases, [.glass, .film, .bar, .noir, .dataPaper])
        XCTAssertEqual(
            AppTheme.visibleCases,
            [.glass, .film, .bar, .noir]
        )
    }

    func testUnknownStoredThemeFallsBackToNoir() {
        XCTAssertEqual(AppTheme.resolve(stored: nil), .noir)
        XCTAssertEqual(AppTheme.resolve(stored: "mystery"), .noir)
        // A stored Ash Veil selection (theme removed) also resolves to `.noir`.
        XCTAssertEqual(AppTheme.resolve(stored: "ashVeil"), .noir)
        // A stored Bento Grid selection (theme removed) also resolves to `.noir`.
        XCTAssertEqual(AppTheme.resolve(stored: "bento"), .noir)
    }
}
