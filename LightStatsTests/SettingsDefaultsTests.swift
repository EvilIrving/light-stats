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

    private func freshSettings(proGiftEnabled: Bool = AppConfig.proGiftEnabled) -> SettingsManager {
        let settings = SettingsManager(defaults: cleanDefaults, proGiftEnabled: proGiftEnabled)
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
        XCTAssertFalse(s.scrollDisableAcceleration)
        XCTAssertFalse(s.scrollIncludeTrackpad)
    }

    func testScrollLinesDefault() {
        XCTAssertEqual(freshSettings().scrollLines, 3)
    }

    func testWindowManagementDefaultsOff() {
        XCTAssertFalse(freshSettings().windowManagementEnabled)
    }

    func testDisplayBrightnessControlDefaultsOff() {
        XCTAssertFalse(freshSettings().displayBrightnessControlEnabled)
    }

    func testKeepAwakeDefaultsOff() {
        XCTAssertFalse(freshSettings().keepAwakeEnabled)
    }

    func testFindMouseDefaultsOffWithLeftControlTrigger() {
        let settings = freshSettings()
        XCTAssertFalse(settings.findMouseEnabled)
        XCTAssertEqual(settings.findMouseTriggerKey, .leftControl)
    }

    func testActivationCodeDefaultsNil() {
        XCTAssertNil(freshSettings().activationCode)
    }

    // MARK: - Permanent Pro gift

    func testGiftPeriodGrantsProToCleanInstall() {
        XCTAssertTrue(freshSettings().isGrandfathered)
        XCTAssertEqual(cleanDefaults.object(forKey: "settings.grandfathered") as? Bool, true)
    }

    func testGiftPeriodUpgradesAnEarlierFalseMarker() {
        cleanDefaults.set(false, forKey: "settings.grandfathered")

        XCTAssertTrue(freshSettings().isGrandfathered)
        XCTAssertEqual(cleanDefaults.object(forKey: "settings.grandfathered") as? Bool, true)
    }

    func testPaidReleaseLocksCleanInstall() {
        XCTAssertFalse(freshSettings(proGiftEnabled: false).isGrandfathered)
        XCTAssertEqual(cleanDefaults.object(forKey: "settings.grandfathered") as? Bool, false)
    }

    func testPaidReleaseStillGrantsUpgradingUserWithoutMarker() {
        cleanDefaults.set(true, forKey: "settings.autoCheckUpdates")

        XCTAssertTrue(freshSettings(proGiftEnabled: false).isGrandfathered)
    }

    func testPermanentGiftSurvivesPaidRelease() {
        cleanDefaults.set(true, forKey: "settings.grandfathered")

        XCTAssertTrue(freshSettings(proGiftEnabled: false).isGrandfathered)
    }

    func testPaidReleaseKeepsStoredFalseDecision() {
        cleanDefaults.set(false, forKey: "settings.grandfathered")
        cleanDefaults.set(true, forKey: "settings.showLogo")

        XCTAssertFalse(freshSettings(proGiftEnabled: false).isGrandfathered)
    }

    /// Regression: `save(_:for:)` must detect nil optionals — `set(_:forKey:)` bridges a
    /// nil optional to NSNull and throws NSInvalidArgumentException (deactivate crashed).
    func testNilOptionalDetection() {
        let nilString: String? = nil
        XCTAssertTrue(SettingsManager.isNilOptional(nilString))
        XCTAssertFalse(SettingsManager.isNilOptional("x"))
        XCTAssertFalse(SettingsManager.isNilOptional(true))
        XCTAssertFalse(SettingsManager.isNilOptional(3))
        XCTAssertFalse(SettingsManager.isNilOptional(Int?.some(3)))
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
        XCTAssertEqual(AppTheme.allCases, [.glass, .film, .bar, .noir, .dataPaper])
    }

    func testStoredGlassThemeRemainsGlass() {
        cleanDefaults.set("glass", forKey: "settings.appTheme")
        XCTAssertEqual(freshSettings().appTheme, .glass)
    }

    func testStoredHiddenThemeFallsBackToNoir() {
        // Data Paper is temporarily hidden (isVisible = false); a stored
        // selection must not keep a hidden theme applied.
        cleanDefaults.set("dataPaper", forKey: "settings.appTheme")
        XCTAssertEqual(freshSettings().appTheme, .noir)
        XCTAssertFalse(AppTheme.dataPaper.isVisible)
    }

    func testUnknownStoredThemeFallsBackToNoir() {
        cleanDefaults.set("mystery", forKey: "settings.appTheme")
        XCTAssertEqual(freshSettings().appTheme, .noir)
    }

    func testFilmAppearanceDefaults() {
        let settings = freshSettings()
        XCTAssertTrue(settings.filmGrainEnabled)
        XCTAssertEqual(settings.filmLightFlow, 0.4, accuracy: 0.0001)
    }

    func testBarAppearanceDefaults() {
        let settings = freshSettings()
        XCTAssertTrue(settings.barGrainEnabled)
        XCTAssertEqual(settings.barLightFlow, 0.4, accuracy: 0.0001)
    }

    func testNoirAppearanceDefaults() {
        let settings = freshSettings()
        XCTAssertTrue(settings.noirGrainEnabled)
        XCTAssertEqual(settings.noirLightFlow, 0.4, accuracy: 0.0001)
    }

    func testThemeAppearanceResolverUsesProductSettings() {
        cleanDefaults.set(false, forKey: "settings.filmGrainEnabled")
        cleanDefaults.set(0.65, forKey: "settings.filmLightFlow")
        cleanDefaults.set(false, forKey: "settings.barGrainEnabled")
        cleanDefaults.set(0.8, forKey: "settings.barLightFlow")
        cleanDefaults.set(true, forKey: "settings.noirGrainEnabled")
        cleanDefaults.set(0.2, forKey: "settings.noirLightFlow")
        let settings = freshSettings()

        XCTAssertEqual(settings.themeAppearance(for: .glass), .none)
        XCTAssertEqual(settings.themeAppearance(for: .dataPaper), .none)
        XCTAssertEqual(
            settings.themeAppearance(for: .film),
            .film(FilmThemeAppearanceConfiguration(grainEnabled: false, lightFlow: 0.65))
        )
        XCTAssertEqual(
            settings.themeAppearance(for: .bar),
            .bar(BarThemeAppearanceConfiguration(grainEnabled: false, lightFlow: 0.8))
        )
        XCTAssertEqual(
            settings.themeAppearance(for: .noir),
            .noir(NoirThemeAppearanceConfiguration(grainEnabled: true, lightFlow: 0.2))
        )
    }

    // MARK: - Persisted overrides are honored (DI sanity check)

    func testStoredValueOverridesDefault() {
        cleanDefaults.set(true, forKey: "settings.windowManagementEnabled")
        XCTAssertTrue(freshSettings().windowManagementEnabled)
    }
}
