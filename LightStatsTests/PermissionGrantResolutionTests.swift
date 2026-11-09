//
//  PermissionGrantResolutionTests.swift
//  Light Stats
//

import XCTest
@testable import Light_Stats

/// How the guide decides the grant is settled.
///
/// The table is the whole rule: four things the watcher can notice, and a final permission read. It
/// exists because two of the four signals mean "the user finished", not "the user granted", and
/// reporting a refusal for a grant the user just made is the failure mode this flow must not have.
final class PermissionGrantResolutionTests: XCTestCase {

    // MARK: - The final read wins

    func testAReadableGrantIsGrantedNoMatterWhatBroughtUsHere() {
        for signal in Self.signals {
            XCTAssertEqual(TCCGrantResult.resolve(signal, isGranted: true), .granted,
                           "a permission that reads true is granted; the signal is only the reason we looked")
        }
    }

    // MARK: - Dismissal-style signals

    func testAFinishedPrivacySheetWithAnUnreadableGrantMeansFinishedInSettings() {
        XCTAssertEqual(
            TCCGrantResult.resolve(.settingsDismissed, isGranted: false),
            .finishedInSettings,
            "Screen Recording's preflight is cached per process, so this is the only possible outcome of a real grant"
        )
    }

    func testReturningToTheAppWithAnUnreadableGrantMeansFinishedInSettings() {
        XCTAssertEqual(TCCGrantResult.resolve(.appReactivated, isGranted: false), .finishedInSettings)
    }

    // MARK: - Nothing happened

    func testATimeoutWithNoGrantIsATimeoutNotARefusal() {
        XCTAssertEqual(
            TCCGrantResult.resolve(.timedOut, isGranted: false),
            .timedOut,
            "nothing concluded is not the same fact as the user finishing without granting"
        )
    }

    func testEveryResultHasItsOwnDiagnosticName() {
        let names = [TCCGrantResult.granted, .finishedInSettings, .timedOut].map(\.diagnosticName)
        XCTAssertEqual(Set(names).count, 3, "granted / finishedInSettings / timedOut must be readable in the journal")
        XCTAssertFalse(names.contains(where: \.isEmpty))
    }

    func testGrantedIsNeverReportedAsAnythingElse() {
        XCTAssertEqual(TCCGrantResult.resolve(.timedOut, isGranted: true).diagnosticName, "granted")
        XCTAssertEqual(TCCGrantResult.resolve(.settingsDismissed, isGranted: true).diagnosticName, "granted")
    }

    private static let signals: [TCCGrantSignal] = [
        .settingsDismissed,
        .appReactivated,
        .timedOut
    ]
}
