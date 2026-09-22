//
//  WindowPreviewMergeTests.swift
//  Light Stats Tests
//

import ApplicationServices
import XCTest
@testable import Light_Stats

/// The window list the preview surfaces show.
///
/// Every fixture here is the shape measured on this machine, because the whole point of the merge
/// is those shapes: WeChat publishes nine layer-0 windows to the WindowServer and one to
/// Accessibility, Fork six against one, and nearly every AppKit application carries an untitled
/// 500×500 window at the bottom-left of the screen.
final class WindowPreviewMergeTests: XCTestCase {

    // MARK: - Fixtures

    /// A WindowServer entry. `onScreen` defaults to true, because a window offered as a card is one
    /// the user can reach — the fixtures say otherwise only where the measurement did.
    private func entry(
        _ windowID: CGWindowID,
        title: String?,
        width: CGFloat,
        height: CGFloat,
        x: CGFloat = 0,
        y: CGFloat = 0,
        onScreen: Bool = true
    ) -> WindowServerInventory.Entry {
        WindowServerInventory.Entry(
            windowID: windowID,
            processID: 93973,
            bounds: CGRect(x: x, y: y, width: width, height: height),
            title: title,
            layer: 0,
            alpha: 1,
            isOnScreen: onScreen,
            ownerName: "微信"
        )
    }

    private func accessibilityItem(_ windowID: CGWindowID?, title: String) -> WindowPreviewItem {
        WindowPreviewItem(
            id: WindowPreviewItem.identifier(
                processID: 93973,
                windowID: windowID,
                element: AXUIElementCreateApplication(93973)
            ),
            title: title,
            isMinimized: false,
            isOnScreen: true,
            frame: CGRect(x: 100, y: 100, width: 900, height: 600),
            element: AXUIElementCreateApplication(93973),
            processID: 93973,
            appName: "微信",
            bundleIdentifier: "com.tencent.xinWeChat",
            windowID: windowID
        )
    }

    private var application: WindowPreviewMerge.Application {
        WindowPreviewMerge.Application(
            processID: 93973,
            appName: "微信",
            bundleIdentifier: "com.tencent.xinWeChat",
            element: AXUIElementCreateApplication(93973)
        )
    }

    private func merged(
        accessibility: [WindowPreviewItem] = [],
        serverWindows: [WindowServerInventory.Entry]
    ) -> [WindowPreviewItem] {
        WindowPreviewMerge.items(
            accessibility: accessibility,
            serverWindows: serverWindows,
            application: application
        )
    }

    // MARK: - Accounting

    func testAWindowAccessibilityAlreadyNamesIsNotOfferedTwice() {
        let items = merged(
            accessibility: [accessibilityItem(17172, title: "微信")],
            serverWindows: [entry(17172, title: "微信", width: 1042, height: 760)]
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.windowID, 17172)
        XCTAssertFalse(items.first?.needsElementResolution ?? true, "The Accessibility element is the one to act on")
    }

    func testAWindowOnlyTheWindowServerKnowsIsStillOffered() {
        // Fork's other repositories are window tabs: Accessibility lists only the tab that is
        // showing, the other two are ordered out, and every tab reports the frame of the showing
        // one. Clicking such a card presses that tab's button.
        let items = merged(
            accessibility: [accessibilityItem(43064, title: "swift-light-stats")],
            serverWindows: [
                entry(43064, title: "swift-light-stats", width: 900, height: 600, x: 100, y: 100),
                entry(43065, title: "swift-between-us", width: 900, height: 600, x: 100, y: 100, onScreen: false),
                entry(43066, title: "go-magic", width: 900, height: 600, x: 100, y: 100, onScreen: false)
            ]
        )
        XCTAssertEqual(
            items.map(\.title),
            ["swift-light-stats", "swift-between-us", "go-magic"],
            "Fork publishes one window to Accessibility and three to the WindowServer"
        )
        XCTAssertTrue(items[1].needsElementResolution, "A WindowServer-only window resolves its element when clicked")
    }

    /// The reported bug: a freshly opened IINA with nothing playing offered three Dock preview cards
    /// for its one window.
    func testAnOffscreenWindowAccessibilityNeverNamesIsNotOffered() {
        // Measured: IINA pre-creates a 600×432 window per installed plugin at launch and leaves it
        // ordered out for the life of the process — `Window — OpenSubtitles` (`io.iina.opensub`) and
        // `User Scripts — User Scripts` (`io.iina.user-script`), both at the same frame, both
        // absent from `AXWindows`, and both with a title that made them look like real windows.
        let items = merged(
            accessibility: [accessibilityItem(63976, title: "com.colliderli.iina")],
            serverWindows: [
                entry(63975, title: "Window — OpenSubtitles", width: 600, height: 432, x: 980, y: 256, onScreen: false),
                entry(63974, title: "User Scripts — User Scripts", width: 600, height: 432, x: 980, y: 256, onScreen: false)
            ]
        )
        XCTAssertEqual(
            items.map(\.title),
            ["com.colliderli.iina"],
            "A titled off-screen window Accessibility never named is furniture, not a card"
        )
    }

    func testAnOffscreenWindowThatIsNotAWindowTabOfAListedWindowIsNotOffered() {
        // The tab rule is the rectangle, not "anything off screen": a window at a place of its own
        // is not a tab of anything.
        let items = merged(
            accessibility: [accessibilityItem(1, title: "Inbox")],
            serverWindows: [
                entry(2, title: "Archive", width: 400, height: 300, x: 700, y: 700, onScreen: false)
            ]
        )
        XCTAssertEqual(
            items.map(\.title),
            ["Inbox"],
            "An off-screen window that shares its rectangle with no listed window is not a window tab"
        )
    }

    func testAnUntitledWindowServerWindowIsNeverOffered() {
        let items = merged(serverWindows: [
            entry(17172, title: "微信", width: 1042, height: 760),
            entry(39512, title: nil, width: 1486, height: 788),
            entry(39513, title: "", width: 1486, height: 788),
            entry(17175, title: "   ", width: 737, height: 704),
            entry(500, title: nil, width: 500, height: 500)
        ])
        XCTAssertEqual(items.map(\.title), ["微信"], "An untitled layer-0 window is furniture: a shadow, a strip, or an offscreen surface")
    }

    func testTheLargerOfTwoWindowServerTwinsWithOneTitleIsKept() {
        let items = merged(serverWindows: [
            entry(17160, title: "微信", width: 280, height: 380),
            entry(17172, title: "微信", width: 1042, height: 760)
        ])
        XCTAssertEqual(items.count, 1, "Two WindowServer windows carrying one title are one window and its twin")
        XCTAssertEqual(items.first?.windowID, 17172, "The larger one is the window; the 280×380 one is the twin")
    }

    // MARK: - Measured shapes

    func testWeChatsNineLayerZeroWindowsBecomeItsTwoRealOnes() {
        // WindowServer: the main window in the process's own list, its untitled twin in the
        // separate WeChat helper process, a full-width 2560×30 strip, three identical 360×288 render
        // surfaces, a transparent 514×520 window, and the 通讯录管理 dialog.
        let items = merged(serverWindows: [
            entry(37322, title: nil, width: 514, height: 520),
            entry(31188, title: nil, width: 360, height: 288),
            entry(30499, title: nil, width: 360, height: 288),
            entry(30432, title: nil, width: 360, height: 288),
            entry(39512, title: nil, width: 1486, height: 788),
            entry(17172, title: "微信", width: 1042, height: 760),
            entry(17160, title: "微信", width: 280, height: 380),
            entry(17175, title: nil, width: 737, height: 704),
            entry(37438, title: "通讯录管理", width: 700, height: 440)
        ])
        XCTAssertEqual(items.map(\.title), ["微信", "通讯录管理"], "Nine layer-0 windows, one main window and one dialog")
    }
    func testTheResultKeepsAccessibilityWindowsFirst() {
        let items = merged(
            accessibility: [accessibilityItem(1, title: "Inbox")],
            serverWindows: [
                entry(2, title: "Sent", width: 900, height: 600),
                entry(1, title: "Inbox", width: 900, height: 600)
            ]
        )
        XCTAssertEqual(items.map(\.title), ["Inbox", "Sent"])
    }

    func testAnApplicationWithNothingToShowProducesNoItems() {
        let items = merged(serverWindows: [entry(500, title: nil, width: 500, height: 500)])
        XCTAssertTrue(items.isEmpty)
    }

    func testOneWindowIsNeverOfferedAsTwoCards() {
        let items = merged(
            accessibility: [
                accessibilityItem(17172, title: "微信"),
                accessibilityItem(17172, title: "微信")
            ],
            serverWindows: []
        )
        XCTAssertEqual(items.count, 1)
    }
}
