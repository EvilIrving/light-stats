//
//  AppWindowPolicyTests.swift
//  Light Stats Tests
//
//  The rule that decides whether the app looks like a menu-bar citizen or an ordinary app.
//
//  It matters because it is the difference between "the Settings window can be reached from ⌘Tab"
//  and "the Settings window exists but macOS refuses to show it anywhere". Every failure is a window
//  the app draws that must *not* pull the app into the Dock, so each one is pinned below.
//

import XCTest
@testable import Light_Stats

final class AppWindowPolicyTests: XCTestCase {

    private func window(
        visible: Bool = true,
        miniaturized: Bool = false,
        normalLevel: Bool = true,
        panel: Bool = false,
        titled: Bool = true
    ) -> AppWindowPolicy.Window {
        AppWindowPolicy.Window(
            isVisible: visible, isMiniaturized: miniaturized,
            isNormalLevel: normalLevel, isPanel: panel, isTitled: titled
        )
    }

    func testAnOrdinaryTitledWindowNeedsTheApp() {
        XCTAssertTrue(AppWindowPolicy.requiresRegularActivation([window()]))
    }

    /// The popover is a `.nonactivatingPanel` at `.statusBar` level: opening it must never put a Dock
    /// icon under the user's cursor, which is the whole reason this predicate is not "has a window".
    func testThePopoverIsNotAnAppWindow() {
        XCTAssertFalse(AppWindowPolicy.requiresRegularActivation([window(normalLevel: false, panel: true)]))
    }

    func testTheIslandAndPreviewsAreNotAppWindows() {
        // The island sits above the menu bar, the shared preview panel above the Dock.
        XCTAssertFalse(AppWindowPolicy.requiresRegularActivation([window(normalLevel: false)]))
    }

    func testTheCleaningOverlayIsNotAnAppWindow() {
        // Borderless, full screen, and above everything: never titled.
        XCTAssertFalse(AppWindowPolicy.requiresRegularActivation([window(titled: false)]))
    }

    func testATransientSavePanelIsNotAnAppWindow() {
        XCTAssertFalse(AppWindowPolicy.requiresRegularActivation([window(panel: true)]))
    }

    func testAHiddenWindowIsNotAnAppWindow() {
        XCTAssertFalse(AppWindowPolicy.requiresRegularActivation([window(visible: false)]))
        XCTAssertFalse(AppWindowPolicy.requiresRegularActivation([]))
    }

    /// One real window among the chrome is what decides it — the app is either a real app or not.
    func testOneRealWindowAmongTheChromeIsEnough() {
        XCTAssertTrue(AppWindowPolicy.requiresRegularActivation([
            window(normalLevel: false, panel: true),
            window(panel: true),
            window(titled: false),
            window()
        ]))
    }

    /// Closing the last real window has to take the Dock icon away again, or the app stays a regular
    /// app for the rest of the session.
    func testLosingTheLastRealWindowReleasesTheApp() {
        XCTAssertFalse(AppWindowPolicy.requiresRegularActivation([window(visible: false)]))
    }

    /// A miniaturised window is off screen but not gone, and its thumbnail is sitting in the Dock.
    /// Taking the Dock icon away underneath it would be the app disappearing while still in use.
    func testAMiniaturisedWindowStillNeedsTheApp() {
        XCTAssertTrue(AppWindowPolicy.requiresRegularActivation([window(visible: false, miniaturized: true)]))
    }
}
