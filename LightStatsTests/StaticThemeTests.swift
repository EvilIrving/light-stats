//
//  StaticThemeTests.swift
//  Light Stats Tests
//

import SwiftUI
import XCTest
@testable import Light_Stats

@MainActor
final class StaticThemeTests: XCTestCase {
    func testCuratedThemesUseStaticArtworkInsteadOfGlass() {
        for theme in [AppTheme.film, AppTheme.noir] {
            let tokens = ThemeTokens.tokens(for: theme)
            XCTAssertTrue(tokens.usesStaticArtwork)
            XCTAssertFalse(tokens.usesGlass)
        }
    }

    func testNativeThemesDoNotUseStaticArtwork() {
        for theme in [AppTheme.glass, AppTheme.bento] {
            let tokens = ThemeTokens.tokens(for: theme)
            XCTAssertFalse(tokens.usesStaticArtwork)
            XCTAssertTrue(tokens.usesGlass)
            XCTAssertEqual(tokens.textureOpacity, 0)
        }
    }

    func testSunGoldAndInkNightOwnOppositeAppearanceSchemes() {
        XCTAssertEqual(ThemeTokens.film.preferredColorScheme, .light)
        XCTAssertEqual(ThemeTokens.noir.preferredColorScheme, .dark)
    }

    func testStaticTextureRemainsRestrained() {
        XCTAssertGreaterThan(ThemeTokens.film.textureOpacity, 0)
        XCTAssertLessThanOrEqual(ThemeTokens.film.textureOpacity, 0.10)
        XCTAssertGreaterThan(ThemeTokens.noir.textureOpacity, 0)
        XCTAssertLessThanOrEqual(ThemeTokens.noir.textureOpacity, 0.05)
    }

    func testPersistedThemeIdentifiersRemainStable() {
        XCTAssertEqual(AppTheme.film.rawValue, "film")
        XCTAssertEqual(AppTheme.noir.rawValue, "noir")
        XCTAssertEqual(AppTheme.resolve(stored: "aurora"), .film)
        XCTAssertEqual(AppTheme.resolve(stored: "paper"), .film)
    }
}
