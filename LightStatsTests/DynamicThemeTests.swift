//
//  DynamicThemeTests.swift
//  Light Stats Tests
//

import SwiftUI
import XCTest
@testable import Light_Stats

@MainActor
final class DynamicThemeTests: XCTestCase {
    func testCuratedThemesUseDynamicMeshInsteadOfGlass() {
        for theme in [AppTheme.film, AppTheme.noir] {
            let tokens = ThemeTokens.tokens(for: theme)
            XCTAssertTrue(tokens.usesMesh)
            XCTAssertFalse(tokens.usesGlass)
        }
    }

    func testNativeThemesDoNotUseDynamicMesh() {
        for theme in [AppTheme.glass, AppTheme.bento] {
            let tokens = ThemeTokens.tokens(for: theme)
            XCTAssertFalse(tokens.usesMesh)
            XCTAssertTrue(tokens.usesGlass)
            XCTAssertEqual(tokens.grainOpacity, 0)
        }
    }

    func testSunGoldAndInkNightUseDarkAppearance() {
        XCTAssertEqual(ThemeTokens.film.preferredColorScheme, .dark)
        XCTAssertEqual(ThemeTokens.noir.preferredColorScheme, .dark)
    }

    func testDynamicThemesShareGrainStrength() {
        XCTAssertGreaterThan(ThemeTokens.film.grainOpacity, 0)
        XCTAssertEqual(ThemeTokens.film.grainOpacity, ThemeTokens.noir.grainOpacity)
    }

    func testPersistedThemeIdentifiersRemainStable() {
        XCTAssertEqual(AppTheme.film.rawValue, "film")
        XCTAssertEqual(AppTheme.noir.rawValue, "noir")
        XCTAssertEqual(AppTheme.resolve(stored: "aurora"), .film)
        XCTAssertEqual(AppTheme.resolve(stored: "paper"), .film)
    }
}
