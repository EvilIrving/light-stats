//
//  DockHoverPolicyTests.swift
//  Light Stats Tests
//

import CoreGraphics
import XCTest
@testable import Light_Stats

/// The rule that decides what travelling along the Dock does.
///
/// The behaviour that matters is what the policy does *not* say: changing icons is never an exit,
/// and the panel already on screen is the reason a settled pointer on the next icon is a transition
/// rather than a first appearance.
final class DockHoverPolicyTests: XCTestCase {

    private func target(_ processID: pid_t, x: CGFloat = 1200) -> DockHoverTarget {
        DockHoverTarget(
            processID: processID,
            appName: "app-\(processID)",
            bundleIdentifier: "com.example.\(processID)",
            itemFrame: CGRect(x: x, y: 20, width: 54, height: 70)
        )
    }

    func testWarmingStartsBeforeThePanelAppears() {
        var state = DockHoverPolicy.State.idle
        let wechat = target(93973)

        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: nil, target: wechat, now: 100), .idle,
                       "The instant the pointer crosses an icon is not a hover")
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: nil, target: wechat, now: 100.07), .warm(wechat))
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: nil, target: wechat, now: 100.10), .idle,
                       "Thumbnails are requested once per icon, not once per poll")
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: nil, target: wechat, now: 100.19), .show(wechat))
    }

    func testTravellingToTheNextIconIsATransitionNotAnAppearance() {
        var state = DockHoverPolicy.State.idle
        let finder = target(100, x: 300)
        let chrome = target(200, x: 360)

        _ = DockHoverPolicy.settled(&state, presented: nil, target: finder, now: 10)
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: nil, target: finder, now: 10.07), .warm(finder))
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: nil, target: finder, now: 10.20), .show(finder))

        // Crossing to the next icon restarts the dwell, and the panel stays on Finder until Chrome
        // has been hovered for the full delay.
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: finder, target: chrome, now: 10.25), .idle)
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: finder, target: chrome, now: 10.31), .warm(chrome))
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: finder, target: chrome, now: 10.38), .idle,
                       "Still not long enough — the panel must not blink across the Dock")
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: finder, target: chrome, now: 10.44), .show(chrome))
    }

    func testCrossingSeveralIconsQuicklyNeverSettles() {
        var state = DockHoverPolicy.State.idle
        var now = 20.0
        for pid in [pid_t(1), 2, 3, 4, 5] {
            XCTAssertEqual(
                DockHoverPolicy.settled(&state, presented: nil, target: target(pid, x: CGFloat(pid) * 60), now: now),
                .idle
            )
            now += 0.033
        }
        XCTAssertEqual(state.candidate?.processID, 5)
        XCTAssertFalse(state.didWarm, "A hand sweeping along the Dock must not start a capture per icon")
    }

    func testTheApplicationAlreadyOnScreenIsNotShownAgain() {
        var state = DockHoverPolicy.State.idle
        let music = target(19101)
        _ = DockHoverPolicy.settled(&state, presented: music, target: music, now: 5)
        _ = DockHoverPolicy.settled(&state, presented: music, target: music, now: 5.07)
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: music, target: music, now: 5.50), .idle,
                       "Re-reading the same application's windows is not another transition")
    }

    func testMagnifyingUnderThePointerDoesNotRestartTheDwell() {
        var state = DockHoverPolicy.State.idle
        let before = target(42, x: 900)
        let enlarged = DockHoverTarget(
            processID: 42,
            appName: "app-42",
            bundleIdentifier: "com.example.42",
            itemFrame: CGRect(x: 880, y: 20, width: 90, height: 100)
        )
        _ = DockHoverPolicy.settled(&state, presented: nil, target: before, now: 30)
        XCTAssertEqual(DockHoverPolicy.settled(&state, presented: nil, target: enlarged, now: 30.19), .warm(enlarged),
                       "The icon's rect moving under the pointer must not restart the dwell")
    }
}
