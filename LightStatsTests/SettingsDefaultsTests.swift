//
//  SettingsDefaultsTests.swift
//  Light Stats Tests
//
//  Pins the "zero-intrusion / default-off" product rule into code: on a clean
//  install (empty UserDefaults) every capability beyond read-only monitoring is
//  off, and no opt-in feature silently flips on. `SettingsManager(defaults:)`
//  lets us read those defaults against an isolated suite without touching the
//  real `.standard` domain.
//

import XCTest
@testable import Light_Stats

@MainActor
final class SettingsDefaultsTests: XCTestCase {

    private var suiteName = ""
    private var cleanDefaults: UserDefaults!

    /// In production `SettingsManager.shared` is a process-lifetime singleton and
    /// is never deallocated. Deallocating a fresh instance instead runs its
    /// `@MainActor` deinit, whose back-deployment on macOS 14.x trips a Swift
    /// Concurrency runtime double-free. Retaining every instance we create for
    /// the (short) test process avoids that deinit path — matching how the app
    /// itself never tears the singleton down.
    private static var retained: [SettingsManager] = []

    override func setUp() {
        super.setUp()
        suiteName = "LightStatsTests.\(UUID().uuidString)"
        cleanDefaults = UserDefaults(suiteName: suiteName)
        cleanDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        cleanDefaults.removePersistentDomain(forName: suiteName)
        cleanDefaults = nil
        super.tearDown()
    }

    private func freshSettings() -> SettingsManager {
        let settings = SettingsManager(defaults: cleanDefaults)
        Self.retained.append(settings)
        return settings
    }

    // MARK: - Extra tools must ship OFF

    func testExitNodeDetectionDefaultsOff() {
        XCTAssertFalse(freshSettings().exitNodeDetectionEnabled)
    }

    func testAllThreeAIMonitorsDefaultOff() {
        let s = freshSettings()
        XCTAssertFalse(s.aiMonitorClaudeEnabled)
        XCTAssertFalse(s.aiMonitorCodexEnabled)
        XCTAssertFalse(s.aiMonitorGeminiEnabled)
    }

    func testScrollReversalDefaultsOff() {
        let s = freshSettings()
        XCTAssertFalse(s.scrollReverseEnabled)
        XCTAssertFalse(s.scrollReverseHorizontalEnabled)
    }

    func testWindowManagementDefaultsOff() {
        XCTAssertFalse(freshSettings().windowManagementEnabled)
    }

    // MARK: - Monitoring core defaults (positive controls)

    func testCoreMonitoringDefaultsStayOn() {
        let s = freshSettings()
        XCTAssertTrue(s.showCPU)
        XCTAssertTrue(s.showGPU)
        XCTAssertTrue(s.showMemory)
    }

    func testNoNetworkFeatureIsOnByDefault() {
        let s = freshSettings()
        // Zero outbound on a clean install: even update checks are opt-in now.
        XCTAssertFalse(s.autoCheckUpdates)
        XCTAssertFalse(s.includeBetaUpdates)
        XCTAssertFalse(s.exitNodeDetectionEnabled)
    }

    func testBetaUpdateChannelDefaultsOff() {
        XCTAssertFalse(freshSettings().includeBetaUpdates)
    }

    func testScrollStepMultiplierDefaultsToNeutral() {
        XCTAssertEqual(freshSettings().scrollStepMultiplier, 1.0, accuracy: 0.0001)
    }

    func testDiagnosticLogLevelDefaultsToFull() {
        XCTAssertEqual(freshSettings().diagnosticLogLevel, .full)
    }

    func testAppThemeDefaultsToNoir() {
        // Cold start is Ink Night (raw `.noir`); picker order remains unchanged.
        XCTAssertEqual(freshSettings().appTheme, .noir)
        XCTAssertEqual(AppTheme.allCases, [.glass, .bento, .film, .noir])
    }

    func testStoredGlassThemeRemainsGlass() {
        cleanDefaults.set("glass", forKey: "settings.appTheme")
        XCTAssertEqual(freshSettings().appTheme, .glass)
    }

    func testLegacyAuroraThemeKeyMigratesToFilm() {
        cleanDefaults.set("aurora", forKey: "settings.appTheme")
        XCTAssertEqual(freshSettings().appTheme, .film)
    }

    func testRetiredPaperThemeKeyMigratesToFilm() {
        cleanDefaults.set("paper", forKey: "settings.appTheme")
        XCTAssertEqual(freshSettings().appTheme, .film)
    }

    func testFilmAppearanceDefaults() {
        let settings = freshSettings()
        XCTAssertTrue(settings.filmGrainEnabled)
        XCTAssertEqual(settings.filmLightFlow, 0.4, accuracy: 0.0001)
    }

    func testNoirAppearanceDefaults() {
        let settings = freshSettings()
        XCTAssertTrue(settings.noirGrainEnabled)
        XCTAssertEqual(settings.noirLightFlow, 0.4, accuracy: 0.0001)
    }

    // MARK: - Persisted overrides are honored (DI sanity check)

    func testStoredValueOverridesDefault() {
        cleanDefaults.set(true, forKey: "settings.windowManagementEnabled")
        XCTAssertTrue(freshSettings().windowManagementEnabled)
    }
}
