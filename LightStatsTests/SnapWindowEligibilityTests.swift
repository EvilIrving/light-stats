//
//  SnapWindowEligibilityTests.swift
//  Light Stats Tests
//
//  The three-layer window filter.
//
//  This is the difference between a window manager that feels careful and one that occasionally
//  tiles a Chrome toolbar flyout. Each layer catches a different failure, and each one has a test
//  below that names the failure it prevents.
//

import XCTest
@testable import Light_Stats

final class SnapWindowEligibilityTests: XCTestCase {

    private func candidate(
        role: String? = "AXWindow",
        subrole: String? = "AXStandardWindow",
        title: String? = "Document",
        bundle: String? = "com.example.app",
        executable: String? = "Example",
        frame: CGRect? = CGRect(x: 100, y: 100, width: 800, height: 600),
        minimized: Bool = false,
        fullScreen: Bool = false
    ) -> SnapWindowCandidate {
        SnapWindowCandidate(
            role: role,
            subrole: subrole,
            title: title,
            bundleIdentifier: bundle,
            executableName: executable,
            frame: frame,
            isMinimized: minimized,
            isFullScreen: fullScreen
        )
    }

    private func rejection(
        _ candidate: SnapWindowCandidate,
        exclusions: Set<String> = [],
        honorsRestrictedList: Bool = true
    ) -> String? {
        SnapWindowEligibility.rejection(
            for: candidate,
            userExclusions: exclusions,
            honorsRestrictedList: honorsRestrictedList
        )
    }

    // MARK: - Layer 1: is it a window at all

    func testAStandardWindowIsEligible() {
        XCTAssertNil(rejection(candidate()))
        XCTAssertNil(rejection(candidate(subrole: "AXDocumentWindow")))
        XCTAssertNil(rejection(candidate(subrole: "AXFloatingWindow")))
    }

    func testPanelsAndPopoversAreNotEligible() {
        XCTAssertEqual(rejection(candidate(subrole: "AXDialog")), "subrole-AXDialog")
        XCTAssertEqual(rejection(candidate(subrole: "AXSystemDialog")), "subrole-AXSystemDialog")
        XCTAssertEqual(rejection(candidate(subrole: "AXSheet")), "subrole-AXSheet")
    }

    func testANonWindowRoleIsNotEligibleWhenNoSubroleIsReported() {
        XCTAssertEqual(rejection(candidate(role: "AXButton", subrole: nil)), "role-AXButton")
        // A bare AXWindow with no subrole is still a window.
        XCTAssertNil(rejection(candidate(role: "AXWindow", subrole: nil)))
    }

    // MARK: - Layer 2: apps we must leave alone

    func testRestrictedAppsAreRejected() {
        XCTAssertEqual(rejection(candidate(bundle: "org.videolan.vlc")), "restricted-app")
        XCTAssertEqual(rejection(candidate(bundle: "com.valvesoftware.steam")), "restricted-app")
        XCTAssertEqual(rejection(candidate(bundle: "com.microsoft.rdc.macos")), "restricted-app")
    }

    func testJetBrainsAndAndroidStudioAreRejectedByPrefix() {
        XCTAssertEqual(rejection(candidate(bundle: "com.jetbrains.intellij")), "restricted-app")
        XCTAssertEqual(rejection(candidate(bundle: "com.jetbrains.pycharm.ce")), "restricted-app")
        XCTAssertEqual(rejection(candidate(bundle: "com.google.android.studio")), "restricted-app")
        // A bundle that merely starts with the same word is not a JetBrains app.
        XCTAssertNil(rejection(candidate(bundle: "com.jetbrainslike.app")))
    }

    func testWineIsRejectedByProcessName() {
        XCTAssertEqual(
            rejection(candidate(bundle: "com.example.wine", executable: "wine64-preloader")),
            "restricted-process"
        )
    }

    /// Browsers, Finder, and Electron chat clients are windows people snap all day. Wins excludes
    /// them by default; shipping that would make the feature look broken, so they are opt-in.
    func testCommonAppsAreNotRejectedByDefault() {
        for bundle in ["com.google.Chrome", "com.apple.finder", "com.hammerandchisel.discord"] {
            XCTAssertNil(rejection(candidate(bundle: bundle)), bundle)
        }
    }

    func testUserExclusionsAreHonoured() {
        XCTAssertEqual(
            rejection(candidate(bundle: "com.example.app"), exclusions: ["com.example.app"]),
            "excluded-app"
        )
    }

    func testTheRestrictedListCanBeTurnedOff() {
        XCTAssertNil(rejection(candidate(bundle: "org.videolan.vlc"), honorsRestrictedList: false))
        // The user's own list is never negotiable.
        XCTAssertEqual(
            rejection(
                candidate(bundle: "org.videolan.vlc"),
                exclusions: ["org.videolan.vlc"],
                honorsRestrictedList: false
            ),
            "excluded-app"
        )
    }

    // MARK: - Layer 3: geometry and title heuristics

    /// An untitled floating window is a flyout, not a document; tiling it is the classic "why did
    /// my app do that". An untitled standard or document window is just a new window.
    func testUntitledNonStandardWindowsAreRejected() {
        XCTAssertEqual(
            rejection(candidate(subrole: "AXFloatingWindow", title: "")),
            "untitled-non-standard"
        )
        XCTAssertEqual(rejection(candidate(subrole: nil, title: "  ")), "untitled-non-standard")
    }

    func testUntitledStandardWindowsAreKept() {
        XCTAssertNil(rejection(candidate(subrole: "AXStandardWindow", title: "")))
        XCTAssertNil(rejection(candidate(subrole: "AXDocumentWindow", title: "   ")))
    }

    func testElectronModalWidgetsAreRejected() {
        XCTAssertEqual(
            rejection(candidate(title: "modalwebviewwidget")),
            "electron-modal-widget"
        )
        XCTAssertEqual(
            rejection(candidate(title: "Some ModalWebViewWidget Frame")),
            "electron-modal-widget"
        )
    }

    func testTinyWindowsAreRejected() {
        XCTAssertEqual(
            rejection(candidate(frame: CGRect(x: 0, y: 0, width: 20, height: 20))),
            "tooSmall"
        )
    }

    func testAWindowWithNoFrameIsRejected() {
        XCTAssertEqual(rejection(candidate(frame: nil)), "noFrame")
    }

    func testMinimizedAndFullScreenWindowsAreRejected() {
        XCTAssertEqual(rejection(candidate(minimized: true)), "minimized")
        XCTAssertEqual(rejection(candidate(fullScreen: true)), "fullScreen")
    }

    // MARK: - Recommended list

    func testRecommendedListIncludesTheRestrictedSet() {
        let recommended = SnapWindowEligibility.recommendedExclusionSet
        for bundle in SnapWindowEligibility.restrictedBundleIdentifiers {
            XCTAssertTrue(recommended.contains(bundle), bundle)
        }
        XCTAssertTrue(recommended.contains("com.google.Chrome"))
    }
}
