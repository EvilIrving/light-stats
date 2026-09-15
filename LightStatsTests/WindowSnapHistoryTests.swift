//
//  WindowSnapHistoryTests.swift
//  Light Stats Tests
//
//  Restore semantics.
//
//  The bug this file exists for: the previous implementation only recorded an original frame inside
//  its own placement path, so any snap the system's tiling item handled returned early and left the
//  window permanently unrestorable. The second, subtler rule is that a restore point is only
//  meaningful while the window is still where we left it — once the user drags it somewhere else,
//  "restore" would throw the window back to a rectangle from several actions ago.
//

import XCTest
@testable import Light_Stats

final class WindowSnapHistoryTests: XCTestCase {

    private let original = CGRect(x: 100, y: 200, width: 800, height: 600)
    private let snapped = CGRect(x: 0, y: 38, width: 756, height: 944)

    func testPrepareRecordsTheRestorePoint() {
        var history = WindowSnapHistory<String>()
        history.prepare(key: "w", currentFrame: original)
        XCTAssertEqual(history.record(for: "w")?.original, original)
        XCTAssertEqual(history.record(for: "w")?.placed, original)
    }

    /// Consecutive snaps keep the *first* restore point: snapping left then top then bottom should
    /// still return the window to where it was before any of them.
    func testRepeatedPlacementsKeepTheOriginalRestorePoint() {
        var history = WindowSnapHistory<String>()
        history.prepare(key: "w", currentFrame: original)
        history.recordPlacement(key: "w", frame: snapped)

        let secondSnap = CGRect(x: 0, y: 38, width: 1512, height: 472)
        history.prepare(key: "w", currentFrame: snapped)
        history.recordPlacement(key: "w", frame: secondSnap)

        XCTAssertEqual(history.record(for: "w")?.original, original)
        XCTAssertEqual(history.record(for: "w")?.placed, secondSnap)
    }

    func testRestoreReturnsTheOriginalFrame() {
        var history = WindowSnapHistory<String>()
        history.prepare(key: "w", currentFrame: original)
        history.recordPlacement(key: "w", frame: snapped)

        XCTAssertTrue(history.canRestore(key: "w", currentFrame: snapped))
        XCTAssertEqual(history.takeRestoreFrame(key: "w", currentFrame: snapped), original)
    }

    func testRestoreConsumesTheRecord() {
        var history = WindowSnapHistory<String>()
        history.prepare(key: "w", currentFrame: original)
        history.recordPlacement(key: "w", frame: snapped)
        _ = history.takeRestoreFrame(key: "w", currentFrame: snapped)

        XCTAssertNil(history.record(for: "w"))
        XCTAssertFalse(history.canRestore(key: "w", currentFrame: snapped))
        XCTAssertNil(history.takeRestoreFrame(key: "w", currentFrame: snapped))
    }

    /// The window is no longer where we put it, so the user moved it. A restore to a rectangle from
    /// before that move would be worse than doing nothing.
    func testRestoreIsRefusedAfterSomeoneElseMovedTheWindow() {
        var history = WindowSnapHistory<String>()
        history.prepare(key: "w", currentFrame: original)
        history.recordPlacement(key: "w", frame: snapped)

        let userMoved = snapped.offsetBy(dx: 300, dy: 120)
        XCTAssertFalse(history.canRestore(key: "w", currentFrame: userMoved))
        XCTAssertNil(history.takeRestoreFrame(key: "w", currentFrame: userMoved))
    }

    /// And the stale record is replaced, so the window's new position becomes the restore point for
    /// the next snap — that is Wins' `updateRestoreRect`, decided automatically.
    func testPrepareReplacesAStaleRestorePoint() {
        var history = WindowSnapHistory<String>()
        history.prepare(key: "w", currentFrame: original)
        history.recordPlacement(key: "w", frame: snapped)

        let userMoved = snapped.offsetBy(dx: 300, dy: 120)
        history.prepare(key: "w", currentFrame: userMoved)

        XCTAssertEqual(history.record(for: "w")?.original, userMoved)
    }

    /// A window sitting exactly where it started has nothing to restore *to*.
    func testRestoreIsRefusedWhenTheWindowNeverMoved() {
        var history = WindowSnapHistory<String>()
        history.prepare(key: "w", currentFrame: original)
        XCTAssertFalse(history.canRestore(key: "w", currentFrame: original))
    }

    func testRestoreIsRefusedWithoutARecord() {
        let history = WindowSnapHistory<String>()
        XCTAssertFalse(history.canRestore(key: "w", currentFrame: original))
    }

    func testPlacementWithoutAPriorPrepareStillCreatesARecord() {
        var history = WindowSnapHistory<String>()
        history.recordPlacement(key: "w", frame: snapped)
        XCTAssertEqual(history.record(for: "w")?.original, snapped)
        XCTAssertEqual(history.record(for: "w")?.placed, snapped)
    }

    func testForgetAndRemoveAll() {
        var history = WindowSnapHistory<String>()
        history.prepare(key: "a", currentFrame: original)
        history.prepare(key: "b", currentFrame: original)
        XCTAssertEqual(history.count, 2)

        history.forget(key: "a")
        XCTAssertEqual(history.count, 1)

        history.removeAll()
        XCTAssertEqual(history.count, 0)
    }

    /// Windows are compared with a tolerance, because an app that clamps its own frame by a point
    /// still moved where we asked it to and restore must stay available.
    func testRestoreToleratesAClampedPlacement() {
        var history = WindowSnapHistory<String>()
        history.prepare(key: "w", currentFrame: original)
        history.recordPlacement(key: "w", frame: snapped)
        let clamped = snapped.insetBy(dx: 0, dy: 1)
        XCTAssertTrue(history.canRestore(key: "w", currentFrame: clamped))
    }
}

final class SnapMarginsTests: XCTestCase {

    func testZeroIsTheFeatureOffState() {
        XCTAssertTrue(SnapMargins.zero.isZero)
        XCTAssertFalse(SnapMargins(outer: 1, inner: 0).isZero)
    }

    func testHalfInnerIsHalf() {
        XCTAssertEqual(SnapMargins(outer: 0, inner: 20).halfInner, 10)
    }

    func testNegativeValuesClampToZero() {
        let margins = SnapMargins(outer: -5, inner: -1)
        XCTAssertEqual(margins.outer, 0)
        XCTAssertEqual(margins.inner, 0)
    }

    func testCodableRoundTrip() throws {
        let margins = SnapMargins(outer: 12, inner: 8)
        let data = try JSONEncoder().encode(margins)
        XCTAssertEqual(try JSONDecoder().decode(SnapMargins.self, from: data), margins)
    }
}

final class WindowSnapActionTests: XCTestCase {

    /// `titleKey` is spelled out rather than derived from the raw value, so this is the test that
    /// keeps it complete when a case is added.
    func testEveryActionHasAUniqueNonEmptyTitleKey() {
        let keys = WindowSnapAction.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        for key in keys {
            XCTAssertTrue(key.hasPrefix("window.action."), key)
            XCTAssertGreaterThan(key.count, "window.action.".count, key)
        }
    }

    /// The raw value is what a recorded shortcut stores, so renaming a case would silently drop the
    /// user's binding. This pins it.
    func testRawValuesAreStable() {
        XCTAssertEqual(WindowSnapAction.leftHalf.rawValue, "leftHalf")
        XCTAssertEqual(WindowSnapAction.rightTwoThirds.rawValue, "rightTwoThirds")
        XCTAssertEqual(WindowSnapAction.previousDisplay.rawValue, "previousDisplay")
        XCTAssertEqual(WindowSnapAction.allCases.count, 21)
        XCTAssertEqual(WindowSnapAction.closeWindow.rawValue, "closeWindow")
        XCTAssertEqual(WindowSnapAction.quitApplication.rawValue, "quitApplication")
        XCTAssertNotNil(WindowSnapAction(rawValue: "bottomLeft"))
    }

    func testDisplayMovesAreFlagged() {
        XCTAssertTrue(WindowSnapAction.nextDisplay.isDisplayMove)
        XCTAssertTrue(WindowSnapAction.previousDisplay.isDisplayMove)
        XCTAssertFalse(WindowSnapAction.maximize.isDisplayMove)
    }
}
