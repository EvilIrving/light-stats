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
        let metrics = AppSwitcherLayout.metrics(windowCount: 3, appCount: 3, available: wide, showsAppRow: true)
        XCTAssertEqual(metrics.cardSize.width, AppSwitcherLayout.preferredCardWidth, accuracy: 0.5)
        XCTAssertEqual(metrics.visibleWindowCount, 3)
        XCTAssertEqual(metrics.overflowCount, 0)
        XCTAssertLessThanOrEqual(metrics.panelSize.width, wide.width)
    }

    func testManyWindowsShrinkTheCardsRatherThanOverflowing() {
        let metrics = AppSwitcherLayout.metrics(windowCount: 8, appCount: 4, available: wide, showsAppRow: false)
        XCTAssertLessThan(metrics.cardSize.width, AppSwitcherLayout.preferredCardWidth)
        XCTAssertGreaterThanOrEqual(metrics.cardSize.width, AppSwitcherLayout.minimumCardWidth)
        XCTAssertLessThanOrEqual(metrics.panelSize.width, wide.width)
    }

    /// Past a point shrinking stops helping; the remainder is summarised instead of becoming
    /// unreadable.
    func testVeryManyWindowsBecomeAnOverflowCount() {
        let metrics = AppSwitcherLayout.metrics(windowCount: 60, appCount: 6, available: wide, showsAppRow: true)
        XCTAssertEqual(metrics.cardSize.width, AppSwitcherLayout.minimumCardWidth, accuracy: 0.5)
        XCTAssertGreaterThan(metrics.overflowCount, 0)
        XCTAssertEqual(metrics.visibleWindowCount + metrics.overflowCount, 60)
        XCTAssertLessThanOrEqual(metrics.panelSize.width, wide.width)
    }

    func testTheAppRowAddsHeight() {
        let withRow = AppSwitcherLayout.metrics(windowCount: 2, appCount: 4, available: wide, showsAppRow: true)
        let without = AppSwitcherLayout.metrics(windowCount: 2, appCount: 4, available: wide, showsAppRow: false)
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

/// The pointer's half of the switcher.
///
/// Hovering and clicking go through exactly the same session calls the keyboard uses — that is what
/// keeps one selection model instead of two — so what is worth pinning down is the translation from
/// a pointer target to that call, and that a click ends the session on the window it points at.
final class AppSwitcherPointerTests: XCTestCase {

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

    private func session(groups: [(pid_t, Int)]) -> AppSwitcherSession {
        AppSwitcherSession(groups: groups.map { processID, count in
            ApplicationWindowGroup(
                processID: processID,
                appName: "App \(processID)",
                bundleIdentifier: "com.example.app\(processID)",
                windows: (0..<count).map { item(processID, "w\($0)") }
            )
        })
    }

    func testHoveringAnApplicationSelectsItsFirstWindow() {
        var subject = session(groups: [(1, 3), (2, 2)])
        AppSwitcherService.apply(.application(0), to: &subject)
        XCTAssertEqual(subject.selectedGroup?.processID, 1)
        XCTAssertEqual(subject.windowIndex, 0, "arriving at an application starts at its first window")
    }

    func testHoveringAWindowSelectsThatWindow() {
        var subject = session(groups: [(1, 3), (2, 2)])
        AppSwitcherService.apply(.application(0), to: &subject)
        AppSwitcherService.apply(.window(2), to: &subject)
        XCTAssertEqual(subject.selectedWindow?.title, "w2")
    }

    /// The window strip only ever draws the selected application's windows, so a pointer's window
    /// index is relative to that application. Out of range means the pointer was over something that
    /// is not a card, and nothing should move.
    func testAWindowTargetOnlyAppliesToTheApplicationOnScreen() {
        var subject = session(groups: [(1, 3), (2, 2)])
        AppSwitcherService.apply(.window(2), to: &subject)
        XCTAssertEqual(subject.windowIndex, 0, "the application on screen has two windows")
    }

    func testAPointerTargetOutsideTheListChangesNothing() {
        var subject = session(groups: [(1, 2), (2, 2)])
        let group = subject.groupIndex
        AppSwitcherService.apply(.application(9), to: &subject)
        AppSwitcherService.apply(.window(9), to: &subject)
        XCTAssertEqual(subject.groupIndex, group)
        XCTAssertEqual(subject.windowIndex, 0)
    }

    /// A click is a commit: it must return the hovered window *and* end the session, so the ⌘
    /// release that follows finds nothing to do instead of switching a second time.
    func testClickingCommitsTheWindowItPointsAt() {
        var subject = session(groups: [(1, 3), (2, 2)])
        AppSwitcherService.apply(.window(1), to: &subject)
        XCTAssertEqual(subject.commit()?.title, "w1")
        XCTAssertFalse(subject.isShowing)
        XCTAssertNil(subject.commit())
    }
}

/// While a session is open the pointer is modal: the panel takes the click, and everywhere else is
/// swallowed. Decided by a pure function so the rule is testable rather than buried in the tap.
final class AppSwitcherClickShieldTests: XCTestCase {

    private let panel = CGRect(x: 100, y: 100, width: 400, height: 200)

    func testWithNoSessionNothingIsSwallowed() {
        XCTAssertFalse(
            AppSwitcherService.swallowsClick(isShowing: false, panelFrame: panel, point: CGPoint(x: 900, y: 900))
        )
    }

    /// The panel is not on screen yet, so there is no rectangle to be outside of.
    func testWithoutAFrameNothingIsSwallowed() {
        XCTAssertFalse(
            AppSwitcherService.swallowsClick(isShowing: true, panelFrame: nil, point: CGPoint(x: 0, y: 0))
        )
    }

    func testAClickOnThePanelIsLeftToThePanel() {
        XCTAssertFalse(
            AppSwitcherService.swallowsClick(isShowing: true, panelFrame: panel, point: CGPoint(x: 200, y: 150))
        )
        XCTAssertFalse(
            AppSwitcherService.swallowsClick(isShowing: true, panelFrame: panel, point: panel.origin),
            "the edge belongs to the panel"
        )
    }

    func testAClickAnywhereElseIsSwallowed() {
        XCTAssertTrue(
            AppSwitcherService.swallowsClick(isShowing: true, panelFrame: panel, point: CGPoint(x: 99, y: 150))
        )
        XCTAssertTrue(
            AppSwitcherService.swallowsClick(isShowing: true, panelFrame: panel, point: CGPoint(x: 501, y: 150))
        )
    }
}

/// Sizing the panel for both rows.
///
/// The application strip and the window strip share one panel, so the panel has to be as wide as the
/// wider of the two — a strip that does not fit scrolls, and a scroll bar is the one piece of chrome
/// that makes a switcher look like a web page. Text measurement is the system's font, so these assert
/// the relationships (grows, clamped) rather than pixel values.
final class AppSwitcherAppRowTests: XCTestCase {

    private let screen = CGSize(width: 2_560, height: 1_440)
    private let narrow = CGSize(width: 1_440, height: 900)

    /// A handful of applications get the system's maximum icon size: the row is not stretched, and the
    /// icons do not grow past what the system uses.
    func testAFewApplicationsGetTheMaximumIconSize() {
        let row = AppSwitcherLayout.appRow(count: 3, availableWidth: 2_000)
        XCTAssertEqual(row.iconSize, AppSwitcherLayout.AppChip.maximumIconSize, accuracy: 0.5)
        XCTAssertEqual(row.rows, 1)
    }

    /// More applications, smaller icons — this is the whole point of the system's row. The threshold
    /// is the width, not the count: eighteen icons still fit a 2000pt row at full size.
    func testMoreApplicationsShrinkTheIcons() {
        let few = AppSwitcherLayout.appRow(count: 6, availableWidth: 2_000)
        let many = AppSwitcherLayout.appRow(count: 30, availableWidth: 2_000)
        XCTAssertEqual(few.iconSize, AppSwitcherLayout.AppChip.maximumIconSize, accuracy: 0.5)
        XCTAssertLessThan(many.iconSize, few.iconSize)
        XCTAssertGreaterThanOrEqual(many.iconSize, AppSwitcherLayout.AppChip.minimumIconSize)
    }

    /// Whatever the count, one row of them fits the width it was given.
    func testTheRowFitsTheWidthItWasGiven() {
        for count in 1...24 {
            let row = AppSwitcherLayout.appRow(count: count, availableWidth: 2_000)
            let width = AppSwitcherLayout.appRowWidth(count: count, iconSize: row.iconSize, perRow: row.perRow)
            XCTAssertLessThanOrEqual(width, 2_000.5, "count \(count) does not fit")
            XCTAssertEqual(row.rows, 1, "count \(count) should still be one row")
        }
    }

    /// Past the point where the icons would be too small to read, the row wraps instead — the system
    /// does the same rather than shrinking into illegibility or adding a scroll bar.
    func testAnAbsurdNumberOfApplicationsWrapsInsteadOfShrinking() {
        let row = AppSwitcherLayout.appRow(count: 60, availableWidth: 2_000)
        XCTAssertGreaterThan(row.rows, 1)
        XCTAssertGreaterThanOrEqual(row.iconSize, AppSwitcherLayout.AppChip.minimumIconSize)
        let width = AppSwitcherLayout.appRowWidth(count: 60, iconSize: row.iconSize, perRow: row.perRow)
        XCTAssertLessThanOrEqual(width, 2_000.5)
    }

    /// The panel leaves the screen's edges alone, however many applications are running.
    func testThePanelKeepsTheScreenMargin() {
        let metrics = AppSwitcherLayout.metrics(
            windowCount: 1, appCount: 40, available: screen, showsAppRow: true
        )
        XCTAssertLessThanOrEqual(metrics.panelSize.width, screen.width - AppSwitcherLayout.screenMargin * 2 + 0.5)
    }

    /// The row is what makes the panel wide, and it must never be cut by it.
    func testThePanelIsNeverNarrowerThanTheIconRow() {
        let metrics = AppSwitcherLayout.metrics(
            windowCount: 1, appCount: 12, available: screen, showsAppRow: true
        )
        let row = try? XCTUnwrap(metrics.appRow)
        XCTAssertNotNil(row)
        let width = AppSwitcherLayout.appRowWidth(count: 12, iconSize: row?.iconSize ?? 0, perRow: row?.perRow ?? 1)
        XCTAssertGreaterThanOrEqual(metrics.panelSize.width, width)
    }

    /// One window under a wide icon row: the preview box grows to use the panel, it does not sit in the
    /// corner of an empty rectangle and it does not become a poster.
    func testThePreviewBoxFillsThePanelWhenTheRowIsTheWiderOne() {
        let metrics = AppSwitcherLayout.metrics(
            windowCount: 1, appCount: 12, available: screen, showsAppRow: true
        )
        XCTAssertGreaterThan(metrics.cardSize.width, AppSwitcherLayout.preferredCardWidth)
        XCTAssertLessThanOrEqual(metrics.cardSize.width, AppSwitcherLayout.maximumCardWidth + 0.5)
    }

    /// No application row (a single application is running): the panel hugs its cards.
    func testWithoutTheRowThePanelHugsTheCards() {
        let metrics = AppSwitcherLayout.metrics(
            windowCount: 2, appCount: 1, available: screen, showsAppRow: false
        )
        let content = metrics.cardSize.width * 2 + AppSwitcherLayout.cardSpacing
        XCTAssertEqual(metrics.panelSize.width, content + AppSwitcherLayout.panelPadding * 2, accuracy: 1)
        XCTAssertNil(metrics.appRow)
    }

    func testANarrowScreenStillFits() {
        let metrics = AppSwitcherLayout.metrics(
            windowCount: 4, appCount: 14, available: narrow, showsAppRow: true
        )
        XCTAssertLessThanOrEqual(metrics.panelSize.width, narrow.width)
        XCTAssertGreaterThanOrEqual(metrics.cardSize.width, AppSwitcherLayout.minimumCardWidth)
    }
}
