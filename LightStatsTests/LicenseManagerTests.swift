//
//  LicenseManagerTests.swift
//  Light Stats Tests
//
//  License state semantics: activation codes and the legacy-user permanent grant.
//

import XCTest
@testable import Light_Stats

@MainActor
final class LicenseManagerTests: XCTestCase {

    private var suiteName = ""
    private var cleanDefaults: UserDefaults!

    /// Same retention rationale as SettingsDefaultsTests: a deallocated @MainActor
    /// SettingsManager/LicenseManager trips the Swift Concurrency back-deploy double-free
    /// on macOS 14.x, so instances are kept for the test process.
    private static var retained: [AnyObject] = []

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

    private func freshSettings(proGiftEnabled: Bool = false) -> SettingsManager {
        let settings = SettingsManager(defaults: cleanDefaults, proGiftEnabled: proGiftEnabled)
        Self.retained.append(settings)
        return settings
    }

    private func freshLicense(settings: SettingsManager) -> LicenseManager {
        let license = LicenseManager(settings: settings)
        Self.retained.append(license)
        return license
    }

    // MARK: - Permanent gift gates

    func testGiftPeriodCleanInstallIsUnlocked() {
        let license = freshLicense(settings: freshSettings(proGiftEnabled: true))
        XCTAssertTrue(license.isPremiumUnlocked)
        XCTAssertTrue(license.isFindMouseUnlocked)
    }

    func testPaidReleaseCleanInstallIsLocked() {
        let license = freshLicense(settings: freshSettings())
        XCTAssertFalse(license.isPremiumUnlocked)
        XCTAssertFalse(license.isFindMouseUnlocked)
    }

    func testUpgradingUserIsUnlocked() {
        cleanDefaults.set(true, forKey: "settings.showLogo")
        let settings = freshSettings()
        XCTAssertTrue(settings.isGrandfathered)
        let license = freshLicense(settings: settings)
        XCTAssertTrue(license.isPremiumUnlocked)
        XCTAssertTrue(license.isFindMouseUnlocked)
    }

    // MARK: - Activation wiring

    func testActivateRejectsInvalidCode() {
        let settings = freshSettings()
        let license = freshLicense(settings: settings)
        XCTAssertFalse(license.activate("LS1-AAAA-BBBB-CCCC-DDDD"))
        XCTAssertFalse(license.isActivated)
        XCTAssertFalse(license.isFindMouseUnlocked)
        XCTAssertNil(settings.activationCode)
    }

    func testActivateNormalizesAndPersistsValidCode() {
        let settings = freshSettings()
        let payload = LicensePayload(features: [.findMouse], owner: "Tester", issuedAt: Date())
        let license = LicenseManager(settings: settings) { code in
            code == "LS1VALID" ? payload : nil
        }
        Self.retained.append(license)

        XCTAssertTrue(license.activate(" ls1-valid "))
        XCTAssertEqual(settings.activationCode, "LS1VALID")
        XCTAssertEqual(cleanDefaults.string(forKey: "settings.activationCode"), "LS1VALID")
        XCTAssertTrue(license.isActivated)
        XCTAssertTrue(license.isPremiumUnlocked)
        XCTAssertTrue(license.isFindMouseUnlocked)
    }

    func testDeactivateRemovesStoredCode() {
        let settings = freshSettings()
        let payload = LicensePayload(features: [.findMouse], owner: "Tester", issuedAt: Date())
        let license = LicenseManager(settings: settings) { _ in payload }
        Self.retained.append(license)
        XCTAssertTrue(license.activate("LS1-VALID"))

        license.deactivate()

        XCTAssertNil(settings.activationCode)
        XCTAssertNil(cleanDefaults.object(forKey: "settings.activationCode"))
        XCTAssertFalse(license.isActivated)
        XCTAssertFalse(license.isFindMouseUnlocked)
    }

    func testCoordinatorStopsFindMouseWhenActivationIsRemoved() {
        let settings = freshSettings()
        settings.findMouseEnabled = true
        let payload = LicensePayload(features: [.findMouse], owner: "Tester", issuedAt: Date())
        let license = LicenseManager(settings: settings) { _ in payload }
        Self.retained.append(license)
        let service = FindMouseServiceSpy()
        let coordinator = FindMouseCoordinator(settings: settings, service: service, license: license)
        Self.retained.append(coordinator)
        coordinator.start()
        XCTAssertFalse(service.isRunning)

        XCTAssertTrue(license.activate("LS1-VALID"))
        XCTAssertTrue(service.isRunning)

        license.deactivate()
        XCTAssertFalse(service.isRunning)
        XCTAssertGreaterThan(service.stopCount, 0)
    }
}

private final class FindMouseServiceSpy: FindMouseControlling {
    private(set) var isRunning = false
    private(set) var stopCount = 0

    func start() -> Bool {
        isRunning = true
        return true
    }

    func stop() {
        isRunning = false
        stopCount += 1
    }

    func updateTriggerKey(_ key: FindMouseTriggerKey) {}
}
