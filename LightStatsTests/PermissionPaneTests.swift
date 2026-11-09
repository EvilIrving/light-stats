//
//  PermissionPaneTests.swift
//  Light Stats
//

import XCTest
@testable import Light_Stats

/// Each Privacy pane is one value: its deep link, its name in the card's sentence, and the System
/// Settings window owners it can appear under.
///
/// The deep link is the fragile part — Apple renames the pane's *title* between releases ("Screen
/// Recording" became "Screen & System Audio Recording") while the `?Privacy_…` anchor has stayed
/// put. A typo here sends the user to the wrong pane and the card then points at a list that does not
/// exist, which is exactly the dead end this feature replaced.
final class PermissionPaneTests: XCTestCase {

    func testAccessibilityPaneOpensTheAccessibilityList() {
        XCTAssertEqual(
            PermissionPane.accessibility.settingsURLString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        XCTAssertNotNil(PermissionPane.accessibility.url)
    }

    func testScreenRecordingPaneOpensTheCaptureList() {
        XCTAssertEqual(
            PermissionPane.screenRecording.settingsURLString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
        XCTAssertNotNil(PermissionPane.screenRecording.url)
    }

    func testPanesHaveDistinctNamesForTheCardSentence() {
        let keys = PermissionPane.allCases.map(\.displayNameKey)
        XCTAssertEqual(Set(keys).count, PermissionPane.allCases.count)
        XCTAssertFalse(keys.contains(where: \.isEmpty))
    }

    func testRawValueRoundTripsSoALaunchArgumentCanNameAPane() {
        for pane in PermissionPane.allCases {
            XCTAssertEqual(PermissionPane(rawValue: pane.rawValue), pane)
        }
        XCTAssertEqual(PermissionPane(rawValue: "screenRecording"), .screenRecording)
        XCTAssertNil(PermissionPane(rawValue: "microphone"))
    }

    func testBothSystemSettingsOwnerNamesAreAccepted() {
        XCTAssertTrue(PermissionPane.isSettingsOwner("System Settings"))
        XCTAssertTrue(PermissionPane.isSettingsOwner("System Preferences"),
                      "the pre-Ventura shell must still be recognised, or the card never docks")
    }

    func testAnotherApplicationIsNotTheSettingsWindow() {
        XCTAssertFalse(PermissionPane.isSettingsOwner("Finder"))
        XCTAssertFalse(PermissionPane.isSettingsOwner("System Settings Helper"))
        XCTAssertFalse(PermissionPane.isSettingsOwner(""))
    }
}
