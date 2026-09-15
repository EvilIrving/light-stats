//
//  AppSwitcherTests.swift
//  Light Stats Tests
//
//  The ⌘Tab model: selection, wrapping, window stepping, commit, cancel — plus the key mapping and
//  the panel arithmetic underneath it.
//
//  The event tap itself cannot be tested (it is a C callback on its own thread), which is exactly why
//  everything it decides was pushed into the pieces below.
//

import CoreGraphics
import XCTest
@testable import Light_Stats

final class AppSwitcherSessionTests: XCTestCase {

    private func item(_ processID: pid_t, _ title: String) -> WindowPreviewItem {
        WindowPreviewItem(
            id: "\(processID)-\(title)",
            title: title,
            isMinimized: false,
            isOnScreen: true,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            element: AXUIElementCreateSystemWide(),
            processID: processID,
            appName: "App \(processID)",
            bundleIdentifier: "com.example.app\(processID)",
            windowID: nil
        )
    }

    private func group(_ processID: pid_t, windows: Int) -> ApplicationWindowGroup {
        ApplicationWindowGroup(
            processID: processID,
            appName: "App \(processID)",
            bundleIdentifier: "com.example.app\(processID)",
            windows: (0..<windows).map { item(processID, "w\($0)") }
        )
    }

    private func session(groups: [(pid_t, Int)]) -> AppSwitcherSession {
        AppSwitcherSession(groups: groups.map { group($0.0, windows: $0.1) })
    }

    /// Tapping ⌘Tab once must go somewhere *else*: the current application is the one being looked
    /// at, so macOS selects the previously used one.
    func testOpeningSelectsTheSecondApplication() {
        var subject = session(groups: [(1, 1), (2, 1), (3, 1)])
        XCTAssertEqual(subject.selectedGroup?.processID, 2)

        subject = session(groups: [(1, 1)])
        XCTAssertEqual(subject.selectedGroup?.processID, 1, "with one application there is nowhere else to go")
    }

    func testInitialTabIsNotAdvancedTwiceAndReverseBeginsAtTheLastApp() {
        var subject = session(groups: [(1, 1), (2, 1), (3, 1), (4, 1)])
        subject.selectInitialGroup(backwards: false)
        XCTAssertEqual(subject.commit()?.processID, 2, "One Command-Tab must switch to the previous application")
        subject = session(groups: [(1, 1), (2, 1), (3, 1), (4, 1)])
        subject.selectInitialGroup(backwards: true)
        XCTAssertEqual(subject.commit()?.processID, 4, "Command-Shift-Tab starts at the other end of the list")
    }

    func testEmptyWindowGroupsCannotStartAnEmptySwitcher() {
        let subject = session(groups: [(1, 0), (2, 0)])
        XCTAssertFalse(subject.isShowing)
        XCTAssertNil(subject.selectedWindow)
    }

    func testAdvancingWrapsAround() {
        var subject = session(groups: [(1, 1), (2, 1), (3, 1)])
        subject.selectGroup(at: 2)
        subject.advance(by: 1)
        XCTAssertEqual(subject.selectedGroup?.processID, 1)
        subject.advance(by: -1)
        XCTAssertEqual(subject.selectedGroup?.processID, 3)
    }

    func testEachWindowIsReachableInsideItsApplication() {
        var subject = session(groups: [(1, 3), (2, 2), (3, 1)])
        subject.selectGroup(at: 0)
        XCTAssertEqual(subject.selectedWindow?.title, "w0")
        subject.moveWindow(by: 1)
        XCTAssertEqual(subject.selectedWindow?.title, "w1")
        subject.moveWindow(by: 1)
        XCTAssertEqual(subject.selectedWindow?.title, "w2")
        subject.moveWindow(by: 1)
        XCTAssertEqual(subject.selectedWindow?.title, "w0", "window selection wraps too")
    }

    /// Moving to another application must reset the window selection, or committing would target a
    /// window index that belongs to a different application's list.
    func testChangingApplicationResetsTheWindowSelection() {
        var subject = session(groups: [(1, 3), (2, 2), (3, 1)])
        subject.selectGroup(at: 0)
        subject.moveWindow(by: 2)
        subject.advance(by: 1)
        XCTAssertEqual(subject.windowIndex, 0)
    }

    func testCommitReturnsTheSelectionAndEndsTheSession() {
        var subject = session(groups: [(1, 3), (2, 2), (3, 1)])
        subject.selectGroup(at: 1)
        subject.moveWindow(by: 1)

        let committed = subject.commit()
        XCTAssertEqual(committed?.title, "w1")
        XCTAssertFalse(subject.isShowing)
        XCTAssertNil(subject.selectedWindow)
    }

    func testCancelReturnsNothing() {
        var subject = session(groups: [(1, 1), (2, 1)])
        subject.cancel()
        XCTAssertFalse(subject.isShowing)
        XCTAssertNil(subject.commit())
    }

    func testAnEmptySessionIsNotShowing() {
        let subject = session(groups: [])
        XCTAssertFalse(subject.isShowing)
        XCTAssertNil(subject.selectedGroup)
    }

    func testSingleWindowApplicationIgnoresWindowStepping() {
        var subject = session(groups: [(1, 1), (2, 1)])
        subject.selectGroup(at: 0)
        subject.moveWindow(by: 1)
        XCTAssertEqual(subject.windowIndex, 0)
    }

    func testOutOfRangeSelectionIsIgnored() {
        var subject = session(groups: [(1, 2), (2, 1)])
        subject.selectGroup(at: 9)
        XCTAssertEqual(subject.groupIndex, 1, "the initial selection is unchanged")
        subject.selectWindow(at: 9)
        XCTAssertEqual(subject.windowIndex, 0)
    }
}

final class AppSwitcherKeyTests: XCTestCase {

    private func intent(_ keyCode: Int64, command: Bool = true, shift: Bool = false, showing: Bool) -> AppSwitcherKey {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        return AppSwitcherService.intent(keyCode: keyCode, flags: flags, isShowing: showing)
    }

    func testCommandTabBeginsTheSession() {
        XCTAssertEqual(intent(48, showing: false), .begin(backwards: false))
        XCTAssertEqual(intent(48, shift: true, showing: false), .begin(backwards: true))
    }

    func testTabWithoutCommandIsNotOurs() {
        XCTAssertEqual(intent(48, command: false, showing: false), .passthrough)
        // Even mid-session: a bare Tab is ordinary typing and must reach the application.
        XCTAssertEqual(intent(48, command: false, showing: true), .passthrough)
    }

    func testTabWalksForwardAndBackwardWhileShowing() {
        XCTAssertEqual(intent(48, showing: true), .next)
        XCTAssertEqual(intent(48, shift: true, showing: true), .previous)
    }

    func testArrowsStepBetweenWindowsOnlyWhileShowing() {
        XCTAssertEqual(intent(125, showing: true), .nextWindow)
        XCTAssertEqual(intent(126, showing: true), .previousWindow)
        XCTAssertEqual(intent(125, showing: false), .passthrough)
    }

    /// Escape with ⌘ held would otherwise be a different command; while the switcher is open it has
    /// to mean "never mind".
    func testEscapeCancelsOnlyWhileShowing() {
        XCTAssertEqual(intent(53, showing: true), .cancel)
        XCTAssertEqual(intent(53, showing: false), .passthrough)
    }

    /// Any other key must reach the application, so ⌘Q still quits rather than being swallowed.
    func testOtherKeysPassThroughAndEndTheSession() {
        XCTAssertEqual(intent(12, showing: true), .passthrough)
        XCTAssertEqual(intent(0, showing: true), .passthrough)
    }
}

final class ApplicationOrderingTests: XCTestCase {

    private func group(_ processID: pid_t) -> ApplicationWindowGroup {
        ApplicationWindowGroup(processID: processID, appName: "A\(processID)", bundleIdentifier: nil, windows: [])
    }

    func testMostRecentlyUsedComesFirst() {
        let ordered = ApplicationOrdering.mostRecentlyUsed(
            groups: [group(1), group(2), group(3)],
            recency: [3, 1]
        )
        XCTAssertEqual(ordered.map(\.processID), [3, 1, 2])
    }

    /// An application the tracker has never seen must not be dropped — it just sorts last.
    func testUnseenApplicationsAreKeptAtTheEnd() {
        let ordered = ApplicationOrdering.mostRecentlyUsed(
            groups: [group(1), group(2)],
            recency: []
        )
        XCTAssertEqual(ordered.map(\.processID), [1, 2])
    }

    func testEveryApplicationSurvivesOrdering() {
        let groups = [group(1), group(2), group(3), group(4)]
        let ordered = ApplicationOrdering.mostRecentlyUsed(groups: groups, recency: [4, 2])
        XCTAssertEqual(Set(ordered.map(\.processID)), Set(groups.map(\.processID)))
    }
}

final class AppSwitcherLayoutTests: XCTestCase {

    private let wide = CGSize(width: 1_600, height: 900)

    func testFewWindowsGetThePreferredCardWidth() {
        let metrics = AppSwitcherLayout.metrics(windowCount: 3, available: wide, showsAppRow: true)
        XCTAssertEqual(metrics.cardSize.width, AppSwitcherLayout.preferredCardWidth, accuracy: 0.5)
        XCTAssertEqual(metrics.visibleWindowCount, 3)
        XCTAssertEqual(metrics.overflowCount, 0)
        XCTAssertLessThanOrEqual(metrics.panelSize.width, wide.width)
    }

    func testManyWindowsShrinkTheCardsRatherThanOverflowing() {
        let metrics = AppSwitcherLayout.metrics(windowCount: 8, available: wide, showsAppRow: false)
        XCTAssertLessThan(metrics.cardSize.width, AppSwitcherLayout.preferredCardWidth)
        XCTAssertGreaterThanOrEqual(metrics.cardSize.width, AppSwitcherLayout.minimumCardWidth)
        XCTAssertLessThanOrEqual(metrics.panelSize.width, wide.width)
    }

    /// Past a point shrinking stops helping; the remainder is summarised instead of becoming
    /// unreadable.
    func testVeryManyWindowsBecomeAnOverflowCount() {
        let metrics = AppSwitcherLayout.metrics(windowCount: 60, available: wide, showsAppRow: true)
        XCTAssertEqual(metrics.cardSize.width, AppSwitcherLayout.minimumCardWidth, accuracy: 0.5)
        XCTAssertGreaterThan(metrics.overflowCount, 0)
        XCTAssertEqual(metrics.visibleWindowCount + metrics.overflowCount, 60)
        XCTAssertLessThanOrEqual(metrics.panelSize.width, wide.width)
    }

    func testTheAppRowAddsHeight() {
        let withRow = AppSwitcherLayout.metrics(windowCount: 2, available: wide, showsAppRow: true)
        let without = AppSwitcherLayout.metrics(windowCount: 2, available: wide, showsAppRow: false)
        XCTAssertGreaterThan(withRow.panelSize.height, without.panelSize.height)
    }

    func testPanelIsClampedInsideTheScreen() {
        let available = CGRect(x: 0, y: 0, width: 1_512, height: 950)
        let frame = AppSwitcherLayout.panelFrame(
            size: CGSize(width: 1_100, height: 300),
            available: available
        )
        XCTAssertGreaterThanOrEqual(frame.minX, available.minX)
        XCTAssertLessThanOrEqual(frame.maxX, available.maxX)
        XCTAssertGreaterThanOrEqual(frame.minY, available.minY)
        XCTAssertLessThanOrEqual(frame.maxY, available.maxY)
    }

    func testDockPreviewShrinksForManyWindowsToo() {
        let metrics = DockPreviewLayout.metrics(windowCount: 20, available: wide)
        XCTAssertGreaterThanOrEqual(metrics.cardSize.width, DockPreviewLayout.minimumCardWidth)
        XCTAssertLessThanOrEqual(metrics.panelSize.width, min(wide.width, DockPreviewLayout.maximumPanelWidth))
        XCTAssertEqual(metrics.visibleWindowCount + metrics.overflowCount, 20)
    }
}

final class ScreenRecordingAuthorizationTests: XCTestCase {

    func testGrantedIsAuthorized() {
        XCTAssertEqual(
            ScreenRecordingAuthorization.resolve(isGranted: true, hasRequestedThisSession: false),
            .authorized
        )
    }

    func testNotGrantedAndNeverAskedIsDenied() {
        XCTAssertEqual(
            ScreenRecordingAuthorization.resolve(isGranted: false, hasRequestedThisSession: false),
            .denied
        )
    }

    /// The case a two-state model gets wrong: the user granted it in System Settings, but this
    /// process is still reading false until it restarts.
    func testAskedButStillNotGrantedMeansRestartIsRequired() {
        XCTAssertEqual(
            ScreenRecordingAuthorization.resolve(isGranted: false, hasRequestedThisSession: true),
            .requiresRestart
        )
    }

    /// Granting in-session wins over "we asked", so the restart hint never shows when capture
    /// already works.
    func testGrantedBeatsTheRestartHint() {
        XCTAssertEqual(
            ScreenRecordingAuthorization.resolve(isGranted: true, hasRequestedThisSession: true),
            .authorized
        )
    }
}

final class WindowThumbnailSizingTests: XCTestCase {

    func testPixelWidthIsClampedSoAThumbnailCannotAskForA6KCapture() {
        XCTAssertEqual(WindowThumbnailService.pixelWidth(for: 40), 120)
        XCTAssertEqual(WindowThumbnailService.pixelWidth(for: 190), 190)
        XCTAssertEqual(WindowThumbnailService.pixelWidth(for: 4_000), 720)
    }

    func testHeightPreservesTheWindowAspectRatio() {
        let wide = WindowThumbnailService.pixelHeight(for: CGSize(width: 800, height: 600), width: 400)
        XCTAssertEqual(wide, 300)
        let tall = WindowThumbnailService.pixelHeight(for: CGSize(width: 600, height: 900), width: 400)
        XCTAssertEqual(tall, 600)
    }

    func testDegenerateWindowSizeGetsTheStandardRatio() {
        XCTAssertGreaterThan(WindowThumbnailService.pixelHeight(for: .zero, width: 400), 0)
    }

    /// A very tall window must not produce an absurdly tall capture.
    func testExtremeAspectRatiosAreClamped() {
        XCTAssertLessThanOrEqual(
            WindowThumbnailService.pixelHeight(for: CGSize(width: 100, height: 10_000), width: 400),
            1_200
        )
        XCTAssertGreaterThanOrEqual(
            WindowThumbnailService.pixelHeight(for: CGSize(width: 10_000, height: 10), width: 400),
            80
        )
    }
}
