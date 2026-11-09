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

    /// The default shape is the system's two-level one, and it stays two-level: the flat list exists
    /// for the grid mode and must not move the selection here.
    func testTheDefaultModeIsTwoLevelAndIgnoresTheFlatList() {
        let subject = session(groups: [(1, 2), (2, 2)])
        XCTAssertEqual(subject.mode, .twoLevel)
        XCTAssertEqual(subject.selectedGroup?.processID, 2)
        XCTAssertEqual(subject.selectedWindow?.processID, 2, "the second application's first window")
        XCTAssertEqual(subject.selectedWindow?.title, "w0")
        XCTAssertEqual(subject.flatIndex, 1, "the flat list is built, but it does not select anything here")
    }
}

/// The grid mode: one flat list of every window, ordered by recency.
///
/// The same session serves both shapes, so what has to be pinned down is that in this mode every
/// movement — Tab, the arrows, the pointer — walks `flatWindows`, and that a commit returns what the
/// grid has highlighted.
final class AppSwitcherGridSessionTests: XCTestCase {

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

    private func session(groups: [(pid_t, Int)], backwards: Bool = false) -> AppSwitcherSession {
        var subject = AppSwitcherSession(
            groups: groups.map { processID, count in
                ApplicationWindowGroup(
                    processID: processID,
                    appName: "App \(processID)",
                    bundleIdentifier: "com.example.app\(processID)",
                    windows: (0..<count).map { item(processID, "w\($0)") }
                )
            },
            mode: .grid
        )
        subject.selectInitialGroup(backwards: backwards)
        return subject
    }

    /// One ⌘Tab still goes somewhere else: the grid opens on the window that was used before the
    /// current one, which is the second entry of the flat list.
    func testOpeningSelectsTheSecondWindowInTheFlatOrder() {
        let subject = session(groups: [(1, 2), (2, 2)])
        XCTAssertEqual(subject.mode, .grid)
        XCTAssertEqual(subject.flatWindows.count, 4)
        XCTAssertEqual(subject.flatIndex, 1)
        XCTAssertEqual(subject.selectedWindow?.id, "1-w1")
    }

    func testReverseOpeningStartsAtTheLastWindow() {
        let subject = session(groups: [(1, 2), (2, 2)], backwards: true)
        XCTAssertEqual(subject.flatIndex, 3)
        XCTAssertEqual(subject.selectedWindow?.id, "2-w1")
    }

    /// Tab wraps through the flat list, including across applications, which is the whole difference
    /// from the two-level mode.
    func testTabWrapsThroughEveryWindow() {
        var subject = session(groups: [(1, 2), (2, 2)])
        subject.advance(by: 1)
        XCTAssertEqual(subject.selectedWindow?.id, "2-w0", "Tab crossed from one application to the next")
        subject.advance(by: 1)
        subject.advance(by: 1)
        XCTAssertEqual(subject.selectedWindow?.id, "1-w0", "past the last window it wraps to the first")
        subject.advance(by: -1)
        XCTAssertEqual(subject.selectedWindow?.id, "2-w1", "and backwards it wraps the other way")
    }

    /// The arrows move the same selection as Tab in this mode: there is only one level to move on.
    func testTheArrowsMoveTheSameSelectionAsTab() {
        var byTab = session(groups: [(1, 3), (2, 1)])
        var byArrow = byTab
        byTab.advance(by: 1)
        byArrow.moveWindow(by: 1)
        XCTAssertEqual(byArrow.flatIndex, byTab.flatIndex)
        XCTAssertEqual(byArrow.selectedWindow?.id, byTab.selectedWindow?.id)
    }

    /// A pointer's index addresses the flat list here, not an application's own window list.
    func testPointerIndexAddressesTheFlatList() {
        var subject = session(groups: [(1, 2), (2, 2)])
        subject.selectWindow(at: 2)
        XCTAssertEqual(subject.selectedWindow?.id, "2-w0")
        XCTAssertEqual(subject.selectedWindow?.processID, 2)
        subject.selectWindow(at: 9)
        XCTAssertEqual(subject.flatIndex, 2, "an index off the end changes nothing")
    }

    func testCommitReturnsTheFlatSelectionAndEndsTheSession() {
        var subject = session(groups: [(1, 2), (2, 2)])
        subject.selectWindow(at: 3)
        XCTAssertEqual(subject.commit()?.id, "2-w1")
        XCTAssertFalse(subject.isShowing)
        XCTAssertTrue(subject.flatWindows.isEmpty)
        XCTAssertNil(subject.commit())
    }

    func testCancelReturnsNothingInGridModeToo() {
        var subject = session(groups: [(1, 2), (2, 2)])
        subject.advance(by: 1)
        subject.cancel()
        XCTAssertFalse(subject.isShowing)
        XCTAssertNil(subject.commit())
    }

    /// Applications without windows never contribute to the flat list, so the grid cannot show a
    /// card that has nothing behind it.
    func testWindowlessApplicationsContributeNothingToTheGrid() {
        let subject = session(groups: [(1, 0), (2, 2)])
        XCTAssertEqual(subject.flatWindows.map(\.id), ["2-w0", "2-w1"])
        XCTAssertEqual(subject.selectedWindow?.id, "2-w1")
    }
}

/// The mode has to survive the trip from the setting into the session the panel is handed.
///
/// The ⌘Tab provider in the app returns its own `AppSwitcherSession` — built without a mode, so
/// `.twoLevel` — and the only thing that overrides it is the value `setMode` stored. Losing that
/// override is invisible in the session and layout tests, which pass a mode straight to the
/// initializer, and it is exactly what a user reports as "I chose the grid and got the rail".
///
/// The service here is the real one. `candidateSession` is the seam `beginSession` uses, because a
/// real session needs an active event tap and an Accessibility grant, and a test may create neither.
final class AppSwitcherModePlumbingTests: XCTestCase {

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

    private func groups(_ counts: [(pid_t, Int)]) -> [ApplicationWindowGroup] {
        counts.map { processID, count in
            ApplicationWindowGroup(
                processID: processID,
                appName: "App \(processID)",
                bundleIdentifier: "com.example.app\(processID)",
                windows: (0..<count).map { item(processID, "w\($0)") }
            )
        }
    }

    /// A service whose provider looks like the app's: groups in, and a session built with the default
    /// mode — the shape the plumbing has to correct.
    private func service(_ counts: [(pid_t, Int)]) -> AppSwitcherService {
        let listed = groups(counts)
        let service = AppSwitcherService()
        service.sessionProvider = { AppSwitcherSession(groups: listed) }
        return service
    }

    func testTheSettingDecidesTheModeTheSessionOpensIn() {
        let subject = service([(1, 2), (2, 1), (3, 1)])
        subject.setMode(.grid)

        let session = subject.candidateSession(backwards: false)

        XCTAssertEqual(
            session?.mode, .grid,
            "the provider's own two-level session must not decide the shape the panel draws"
        )
        XCTAssertEqual(session?.flatIndex, 1, "the grid opens on the window used before the current one")
        XCTAssertEqual(session?.selectedWindow?.id, "1-w1")
    }

    /// The other direction, on the same service: the setting reaches the next session, and the
    /// two-level selection keeps meaning `groupIndex` / `windowIndex` rather than the flat list.
    func testSwitchingTheSettingBackAppliesToTheNextSession() {
        let subject = service([(1, 2), (2, 2), (3, 1)])
        subject.setMode(.grid)
        XCTAssertEqual(subject.candidateSession(backwards: false)?.mode, .grid)

        subject.setMode(.twoLevel)
        let session = subject.candidateSession(backwards: false)

        XCTAssertEqual(session?.mode, .twoLevel)
        XCTAssertEqual(session?.groupIndex, 1, "one Command-Tab still lands on the previous application")
        XCTAssertEqual(session?.windowIndex, 0)
        XCTAssertEqual(session?.selectedWindow?.id, "2-w0")
    }

    /// Nothing to switch to means no session at all, in either mode: the tap then passes the event
    /// through so the system switcher appears instead of an empty panel.
    func testWithoutWindowsThereIsNoSession() {
        let subject = AppSwitcherService()
        subject.setMode(.grid)
        XCTAssertNil(subject.candidateSession(backwards: false), "no provider")

        let windowless = groups([(1, 0), (2, 0)])
        subject.sessionProvider = { AppSwitcherSession(groups: windowless, mode: .grid) }
        XCTAssertNil(subject.candidateSession(backwards: false), "two applications without windows")
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

/// The grid mode's arithmetic: every window on the panel at once, so there is no overflow chip and
/// nothing to scroll — the panel wraps into rows and shrinks the tiles instead.
///
/// `WindowPreviewCard` draws its picture at this aspect above a fixed title line, so a tile that does
/// not keep it is a different card, not a smaller one.
final class AppSwitcherGridLayoutTests: XCTestCase {

    private let wide = CGSize(width: 1_600, height: 900)
    private let laptop = CGSize(width: 1_024, height: 640)
    private let screenFraction: CGFloat = 0.9
    private let cardAspect: CGFloat = 0.62

    /// Three windows are the common case: one row, the preferred tile size, and no room reserved for
    /// anything that would have to scroll.
    func testThreeWindowsSitInOneRowAtThePreferredTileSize() {
        let metrics = AppSwitcherGridLayout.metrics(windowCount: 3, available: wide)
        XCTAssertEqual(metrics.columns, 3)
        XCTAssertEqual(metrics.tileSize.width, AppSwitcherGridLayout.preferredTileWidth, accuracy: 0.5)
        XCTAssertEqual(
            metrics.panelSize.width,
            3 * metrics.tileSize.width + 2 * AppSwitcherGridLayout.spacing + AppSwitcherGridLayout.padding * 2,
            accuracy: 0.5
        )
        XCTAssertEqual(
            metrics.panelSize.height,
            metrics.tileSize.height + AppSwitcherGridLayout.padding * 2,
            accuracy: 0.5,
            "one row: the height is a single tile plus the panel's padding"
        )
    }

    /// Six columns is the ceiling whatever the window count — past that the tiles would be too narrow
    /// to read, so the panel grows rows instead.
    func testColumnsNeverExceedTheCap() {
        for count in 1...40 {
            let metrics = AppSwitcherGridLayout.metrics(windowCount: count, available: wide)
            XCTAssertGreaterThanOrEqual(metrics.columns, 1, "count \(count)")
            XCTAssertLessThanOrEqual(metrics.columns, AppSwitcherGridLayout.maximumColumns, "count \(count)")
            XCTAssertLessThanOrEqual(metrics.columns, count, "count \(count)")
        }
    }

    func testTheGridWrapsIntoRowsRatherThanGrowingWide() {
        let metrics = AppSwitcherGridLayout.metrics(windowCount: 7, available: wide)
        XCTAssertEqual(metrics.columns, 4, "seven windows wrap at four rather than adding columns")
        XCTAssertEqual(
            metrics.panelSize.height,
            2 * metrics.tileSize.height + AppSwitcherGridLayout.spacing + AppSwitcherGridLayout.padding * 2,
            accuracy: 0.5
        )
    }

    /// The panel never takes more than 90% of the screen in either direction, on a desktop display and
    /// on a laptop one, for any count a person actually has open.
    func testThePanelStaysInsideNinetyPercentOfTheScreen() {
        for available in [wide, laptop] {
            for count in 1...24 {
                let metrics = AppSwitcherGridLayout.metrics(windowCount: count, available: available)
                XCTAssertLessThanOrEqual(
                    metrics.panelSize.width, available.width * screenFraction + 0.5, "\(count) on \(available)"
                )
                XCTAssertLessThanOrEqual(
                    metrics.panelSize.height, available.height * screenFraction + 0.5, "\(count) on \(available)"
                )
            }
        }
    }

    /// Shrinking stops at a readable width: a tile is never narrower than the minimum, and its height
    /// follows the same aspect the card draws with.
    func testEveryTileKeepsItsMinimumWidthAndTheCardAspect() {
        for available in [wide, laptop] {
            for count in 1...24 {
                let metrics = AppSwitcherGridLayout.metrics(windowCount: count, available: available)
                XCTAssertGreaterThanOrEqual(
                    metrics.tileSize.width,
                    AppSwitcherGridLayout.minimumTileWidth - 0.001,
                    "\(count) on \(available)"
                )
                XCTAssertLessThanOrEqual(
                    metrics.tileSize.width,
                    AppSwitcherGridLayout.preferredTileWidth + 0.001,
                    "\(count) on \(available)"
                )
                XCTAssertEqual(
                    metrics.tileSize.height,
                    metrics.tileSize.width * cardAspect + AppSwitcherLayout.cardTitleHeight,
                    accuracy: 0.5,
                    "a narrow tile must be a smaller card, not a taller one — \(count) on \(available)"
                )
            }
        }
    }

    /// Past the point where rows stop helping, the tiles floor at the readable minimum and the grid
    /// runs past its budget rather than becoming illegible. This is the documented degradation, so it
    /// is asserted rather than left to be rediscovered. The overrun is what `isScrollable` reports;
    /// the panel itself is still capped at 90% of the screen (see the next test).
    func testAnAbsurdNumberOfWindowsFloorsAtTheReadableTile() {
        let metrics = AppSwitcherGridLayout.metrics(windowCount: 60, available: wide)
        XCTAssertEqual(metrics.columns, AppSwitcherGridLayout.maximumColumns)
        XCTAssertEqual(metrics.tileSize.width, AppSwitcherGridLayout.minimumTileWidth, accuracy: 0.5)
    }

    /// The panel is never larger than 90% of the screen, whatever the window count — the counts here
    /// are the ones that actually broke it: 60 windows on a 1512×900 display produced a panel taller
    /// than the screen, so it ran off the display and the selected tile went with it.
    func testThePanelIsCappedAtNinetyPercentOfTheScreenForEveryWindowCount() {
        let screens = [CGSize(width: 1_512, height: 900), CGSize(width: 1_280, height: 720), wide, laptop]
        for available in screens {
            for count in [1, 2, 13, 60, 200] {
                let metrics = AppSwitcherGridLayout.metrics(windowCount: count, available: available)
                XCTAssertLessThanOrEqual(
                    metrics.panelSize.width, available.width * screenFraction + 0.5, "\(count) on \(available)"
                )
                XCTAssertLessThanOrEqual(
                    metrics.panelSize.height, available.height * screenFraction + 0.5, "\(count) on \(available)"
                )
                XCTAssertGreaterThanOrEqual(metrics.columns, 1, "\(count) on \(available)")
                XCTAssertGreaterThanOrEqual(metrics.tileSize.width, 0, "\(count) on \(available)")
                XCTAssertGreaterThanOrEqual(metrics.tileSize.height, 0, "\(count) on \(available)")
                XCTAssertGreaterThan(metrics.contentWidth, 0, "\(count) on \(available)")
            }
        }
    }

    /// The grid scrolls exactly when its rows do not fit the panel, and not before: the two-level
    /// strip's rule, applied to the other axis.
    func testTheGridScrollsOnlyOnceTheRowsOutgrowThePanel() {
        let display = CGSize(width: 1_512, height: 900)
        let three = AppSwitcherGridLayout.metrics(windowCount: 3, available: display)
        XCTAssertFalse(three.isScrollable, "three windows fit: there is nothing to scroll to")
        XCTAssertEqual(three.contentHeight, three.panelSize.height, accuracy: 0.5)

        let many = AppSwitcherGridLayout.metrics(windowCount: 60, available: display)
        XCTAssertTrue(many.isScrollable, "ten rows of readable tiles do not fit a 900pt display")
        XCTAssertGreaterThan(many.contentHeight, many.panelSize.height)
        XCTAssertEqual(
            many.panelSize.height, display.height * screenFraction, accuracy: 0.5,
            "the panel takes its whole budget instead of following the grid off the screen"
        )
    }

    /// Adding windows never *removes* columns: choosing a column count is a search for the narrowest
    /// panel that fits, and a count that needed six columns cannot need four once it grows.
    func testColumnsNeverShrinkAsWindowsAreAdded() {
        for available in [wide, laptop] {
            var previous = 0
            for count in 1...200 {
                let metrics = AppSwitcherGridLayout.metrics(windowCount: count, available: available)
                XCTAssertGreaterThanOrEqual(metrics.columns, previous, "\(count) on \(available)")
                previous = metrics.columns
            }
        }
    }

    /// Content width is the panel minus its padding, and it is never zero or negative — the grid is
    /// laid out against it.
    func testContentWidthIsThePanelMinusItsPadding() {
        let metrics = AppSwitcherGridLayout.metrics(windowCount: 2, available: wide)
        XCTAssertEqual(
            metrics.contentWidth,
            metrics.panelSize.width - AppSwitcherGridLayout.padding * 2,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(metrics.contentWidth, 0)
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
