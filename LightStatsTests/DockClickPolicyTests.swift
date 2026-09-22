//
//  DockClickPolicyTests.swift
//  Light Stats Tests
//
//  The Dock-click decision and the click that feeds it. Both are pure, so every branch that decides
//  whether another application's windows move is covered here instead of by clicking a real Dock.
//

import XCTest
@testable import Light_Stats

final class DockClickPolicyTests: XCTestCase {

    private func candidate(
        pid: pid_t = 4242,
        own: Bool = false,
        running: Bool = true,
        regular: Bool = true,
        frontmost: Bool = true,
        visible: Bool = true,
        collapsible: Bool = true,
        minimized: Bool = false
    ) -> DockClickCandidate {
        DockClickCandidate(
            processID: pid,
            bundleIdentifier: "com.example.editor",
            name: "Editor",
            isOwnApplication: own,
            isRunning: running,
            isRegular: regular,
            wasFrontmost: frontmost,
            hasVisibleWindows: visible,
            hasCollapsibleWindows: collapsible,
            hasMinimizedWindows: minimized
        )
    }

    // MARK: - The decision

    func testTheFrontmostAppWithWindowsIsTheOneThatCollapses() {
        XCTAssertEqual(DockClickPolicy.action(for: candidate(), isCollapsedByUs: false), .collapse(4242),
                       "Clicking the frontmost app's own icon is the one click macOS leaves doing nothing")
    }

    func testAnAppWeCollapsedIsRestoredAndNotCollapsedAgain() {
        let collapsed = candidate(frontmost: true, visible: false, collapsible: false, minimized: true)
        XCTAssertEqual(DockClickPolicy.action(for: collapsed, isCollapsedByUs: true), .restore(4242),
                       "The second click has to be the way back, or the gesture is a one-way trap")
    }

    func testWindowsBroughtBackByHandAreCollapsedAgain() {
        let restored = candidate(frontmost: true, visible: true, collapsible: true, minimized: false)
        XCTAssertEqual(DockClickPolicy.action(for: restored, isCollapsedByUs: true), .collapse(4242),
                       "A record is not a lock: once the user shows windows again, the next click puts them away")
    }

    func testCollapsedWindowsTheUserClosedAreNotRestored() {
        let closed = candidate(frontmost: true, visible: false, collapsible: false, minimized: false)
        XCTAssertEqual(DockClickPolicy.action(for: closed, isCollapsedByUs: true), .pass(reason: "windows-away"),
                       "Nothing is minimized any more, so there is no restore to attempt")
    }

    func testCollapsedWindowsTheDockIsRestoringItselfAreLeftAlone() {
        // Many apps stop publishing a minimized window through AXWindows, and the Dock brings it back
        // on the same click. Claiming that click would fight the system for no reason.
        let away = candidate(frontmost: false, visible: false, collapsible: false, minimized: false)
        XCTAssertEqual(DockClickPolicy.action(for: away, isCollapsedByUs: true), .pass(reason: "windows-away"))
    }

    func testANonFrontmostAppIsLeftToTheDock() {
        let background = candidate(frontmost: false)
        XCTAssertEqual(DockClickPolicy.action(for: background, isCollapsedByUs: false),
                       .pass(reason: "not-frontmost"),
                       "macOS already activates this app; collapsing it would fight the click")
    }

    func testAnAppShowingOnlyAFullScreenWindowIsLeftAlone() {
        let fullScreen = candidate(visible: true, collapsible: false)
        XCTAssertEqual(DockClickPolicy.action(for: fullScreen, isCollapsedByUs: false),
                       .pass(reason: "only-full-screen"),
                       "A full-screen window cannot be minimized, so the click must not be swallowed")
    }

    func testAnAppWithoutWindowsIsLeftAlone() {
        let windowless = candidate(visible: false, collapsible: false, minimized: false)
        XCTAssertEqual(DockClickPolicy.action(for: windowless, isCollapsedByUs: false), .pass(reason: "no-windows"))
    }

    func testOurOwnWindowsAndNonDockAppsAreNeverTouched() {
        XCTAssertEqual(DockClickPolicy.action(for: candidate(own: true), isCollapsedByUs: false), .pass(reason: "own-app"))
        XCTAssertEqual(DockClickPolicy.action(for: candidate(regular: false), isCollapsedByUs: false),
                       .pass(reason: "not-a-dock-app"))
        XCTAssertEqual(DockClickPolicy.action(for: candidate(running: false), isCollapsedByUs: false),
                       .pass(reason: "not-running"))
    }

    // MARK: - Repeat suppression

    func testASecondClickInsideTheToleranceIsSwallowed() {
        let first = DockClickMoment(processID: 42, at: 100)
        XCTAssertTrue(DockClickPolicy.isRepeat(since: first, processID: 42, at: 100.1),
                      "A double click must not collapse and restore in one gesture")
        XCTAssertFalse(DockClickPolicy.isRepeat(since: first, processID: 42, at: 100.5))
        XCTAssertFalse(DockClickPolicy.isRepeat(since: first, processID: 43, at: 100.1),
                       "Another app's icon is a different click, however fast it follows")
        XCTAssertFalse(DockClickPolicy.isRepeat(since: nil, processID: 42, at: 100))
    }

    // MARK: - The gesture

    func testAPressAndReleaseInPlaceIsAClick() {
        var gesture = DockClickGesture()
        gesture.begins(at: CGPoint(x: 100, y: 900), now: 10)
        XCTAssertTrue(gesture.isPending)
        XCTAssertTrue(gesture.ends(at: CGPoint(x: 102, y: 902), now: 10.2))
        XCTAssertFalse(gesture.isPending, "A finished gesture must leave nothing pending")
    }

    func testDraggingADockIconIsNotAClick() {
        var gesture = DockClickGesture()
        gesture.begins(at: CGPoint(x: 100, y: 900), now: 10)
        XCTAssertTrue(gesture.moved(to: CGPoint(x: 140, y: 900)))
        XCTAssertFalse(gesture.isPending)
        XCTAssertFalse(gesture.ends(at: CGPoint(x: 140, y: 900), now: 10.4),
                       "Rearranging the Dock must never collapse a window when the drag ends")
    }

    func testTravelBelowTheToleranceStillCounts() {
        var gesture = DockClickGesture()
        gesture.begins(at: CGPoint(x: 100, y: 900), now: 10)
        XCTAssertFalse(gesture.moved(to: CGPoint(x: 102, y: 901)),
                       "A hand is not a laser; two points of travel is still a click")
        XCTAssertTrue(gesture.ends(at: CGPoint(x: 102, y: 901), now: 10.3))
    }

    func testHoldingAnIconIsNotAClick() {
        var gesture = DockClickGesture()
        gesture.begins(at: CGPoint(x: 100, y: 900), now: 10)
        XCTAssertFalse(gesture.ends(at: CGPoint(x: 100, y: 900), now: 11),
                       "A press and hold opens the Dock's own menu; its release must do nothing")
    }

    func testTravelingAfterThePressAlsoDisqualifiesTheRelease() {
        var gesture = DockClickGesture()
        gesture.begins(at: CGPoint(x: 100, y: 900), now: 10)
        XCTAssertFalse(gesture.ends(at: CGPoint(x: 160, y: 900), now: 10.2),
                       "The release point is what the user aimed at, not the press point")
    }

    func testACancelledGestureIsForgettable() {
        var gesture = DockClickGesture()
        gesture.begins(at: CGPoint(x: 100, y: 900), now: 10)
        gesture.cancel()
        XCTAssertFalse(gesture.isPending)
        XCTAssertFalse(gesture.ends(at: CGPoint(x: 100, y: 900), now: 10.1),
                       "A right click or a switch change cancels the pending click entirely")
    }

    func testAReleaseWithoutAPressIsIgnored() {
        var gesture = DockClickGesture()
        XCTAssertFalse(gesture.ends(at: CGPoint(x: 100, y: 900), now: 10))
    }
}
