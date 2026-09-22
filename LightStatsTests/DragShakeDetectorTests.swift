//
//  DragShakeDetectorTests.swift
//  Light Stats Tests
//
//  The shake gesture, driven by a fake clock.
//
//  This is the kind of thing that is normally only verifiable by waving a mouse at a screen: it has
//  a distance threshold, a time window, a reversal count, and a cooldown, and every one of them can
//  be got wrong in a way that either fires constantly or never fires at all.
//

import XCTest
@testable import Light_Stats

final class DragShakeDetectorTests: XCTestCase {

    private var detector = DragShakeDetector()

    override func setUp() {
        super.setUp()
        detector = DragShakeDetector()
    }

    /// Feeds a stroke of `distance` in one direction, then returns the detector's verdict on the
    /// sample that completes it.
    @discardableResult
    private func stroke(_ direction: CGFloat, distance: CGFloat, at time: TimeInterval) -> Bool {
        // Approach the threshold in small steps so the detector sees a plausible event stream.
        let steps = 6
        var fired = false
        for step in 1...steps {
            fired = detector.update(horizontalDelta: direction * distance / CGFloat(steps), at: time + Double(step) * 0.001) || fired
        }
        return fired
    }

    func testASingleStrokeIsNotAShake() {
        XCTAssertFalse(stroke(1, distance: 80, at: 0))
    }

    func testTwoReversalsIsStillNotEnough() {
        stroke(1, distance: 80, at: 0)
        XCTAssertFalse(stroke(-1, distance: 80, at: 0.05))
    }

    func testThreeReversalsInsideTheWindowFireOnce() {
        stroke(1, distance: 80, at: 0)
        stroke(-1, distance: 80, at: 0.05)
        XCTAssertTrue(stroke(1, distance: 80, at: 0.1))
    }

    /// The same three strokes spread out is somebody repositioning a window, not shaking it.
    func testReversalsSpreadBeyondTheWindowNeverFire() {
        stroke(1, distance: 80, at: 0)
        stroke(-1, distance: 80, at: 0.5)
        XCTAssertFalse(stroke(1, distance: 80, at: 1.0))
    }

    /// Travel in the same direction does not accumulate into a reversal.
    func testContinuingInOneDirectionNeverFires() {
        for step in 0..<10 {
            stroke(1, distance: 80, at: Double(step) * 0.05)
        }
        XCTAssertFalse(detector.update(horizontalDelta: 0, at: 0.6))
    }

    /// Movement smaller than a stroke is noise and must not count toward a reversal.
    func testSmallMovementDoesNotCountAsAStroke() {
        stroke(1, distance: 90, at: 0)
        stroke(-1, distance: 20, at: 0.05)
        XCTAssertFalse(stroke(1, distance: 20, at: 0.1))
    }

    func testCooldownSuppressesASecondShake() {
        XCTAssertTrue(fireShake(startingAt: 0))
        // Immediately shaking again is the same gesture continuing, not a new one.
        XCTAssertFalse(fireShake(startingAt: 0.2))
    }

    func testAShakeCanFireAgainAfterTheCooldown() {
        XCTAssertTrue(fireShake(startingAt: 0))
        XCTAssertTrue(fireShake(startingAt: 2))
    }

    func testResetDropsAnInProgressGesture() {
        stroke(1, distance: 80, at: 0)
        stroke(-1, distance: 80, at: 0.05)
        detector.reset()
        XCTAssertFalse(stroke(1, distance: 80, at: 0.1))
    }

    func testDefaultConfigurationIsDeliberateEnoughToNotFireAccidentally() {
        let configuration = DragShakeDetector.Configuration.default
        XCTAssertGreaterThanOrEqual(configuration.minimumReversals, 3)
        XCTAssertGreaterThan(configuration.strokeDistance, 20)
        XCTAssertGreaterThan(configuration.cooldown, configuration.window)
    }

    /// A shake that could only hide would strand the user with everything hidden and no way back
    /// except a shortcut they may never have bound: the gesture toggles.
    func testShakingAgainBringsBackWhatTheShakeHid() {
        XCTAssertEqual(ShakeVisibilityPolicy.command(hasHiddenApplications: false), .hideOthers)
        XCTAssertEqual(ShakeVisibilityPolicy.command(hasHiddenApplications: true), .restore,
                       "A second shake is the undo for the first")
    }

    private func fireShake(startingAt start: TimeInterval) -> Bool {
        var fired = stroke(1, distance: 80, at: start)
        fired = stroke(-1, distance: 80, at: start + 0.05) || fired
        fired = stroke(1, distance: 80, at: start + 0.1) || fired
        return fired
    }
}

final class SnapTargetCodingTestsExtra: XCTestCase {

    /// The visibility case has to survive a round trip too — it is what a recorded "hide others"
    /// shortcut stores.
    func testVisibilityTargetRoundTrips() throws {
        let target = SnapTarget.visibility(.hideOthers)
        let data = try JSONEncoder().encode(target)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("hideOthers"), json)
        XCTAssertEqual(try JSONDecoder().decode(SnapTarget.self, from: data), target)
    }

    func testVisibilityTargetsAreDistinctFromEachOther() {
        XCTAssertNotEqual(SnapTarget.visibility(.hideAll), SnapTarget.visibility(.hideOthers))
        XCTAssertEqual(SnapTarget.visibility(.restore).diagnosticName, "visibility.restore")
    }

    /// Hiding applications is `NSRunningApplication`'s own API, so it must not be gated behind the
    /// Accessibility permission — that is the whole reason these are separate commands.
    func testVisibilityTargetsDoNotRequireAccessibility() {
        XCTAssertFalse(SnapTarget.visibility(.hideOthers).requiresAccessibility)
        XCTAssertTrue(SnapTarget.action(.leftHalf).requiresAccessibility)
        XCTAssertTrue(SnapTarget.region(.leftHalf).requiresAccessibility)
    }

    /// A non-geometric target must produce no rectangle, or the preview overlay would try to draw
    /// something for a command that is not about position at all.
    func testVisibilityCommandsWithoutGeometryStayOutOfTheGrid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        for command in WindowVisibilityCommand.allCases {
            XCTAssertNil(SnapGridGeometry.frame(for: .visibility(command), in: bounds, margins: .zero), "\(command)")
            XCTAssertNil(WindowPlacementEngine.resolvedFrame(
                for: .visibility(command),
                screen: SnapScreenGeometry(frame: bounds, visibleFrame: bounds),
                margins: .zero,
                currentSize: .zero
            ), "\(command)")
        }
    }

    func testEveryVisibilityCommandHasATitleKey() {
        let keys = WindowVisibilityCommand.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        for key in keys {
            XCTAssertTrue(key.hasPrefix("window.visibility."), key)
        }
    }

    func testOnlyRestoreNeedsSomethingToRestore() {
        XCTAssertTrue(WindowVisibilityCommand.restore.requiresHiddenApplications)
        XCTAssertFalse(WindowVisibilityCommand.hideOthers.requiresHiddenApplications)
        XCTAssertFalse(WindowVisibilityCommand.hideAll.requiresHiddenApplications)
    }

    func testAVisibilityShortcutSurvivesPruning() {
        var configuration = SnapConfiguration.default
        configuration.setShortcut(SnapShortcut(target: .visibility(.hideOthers), keyCode: 4, modifiers: 5))
        configuration.pruneDanglingReferences()
        XCTAssertTrue(configuration.shortcuts.contains { $0.target == .visibility(.hideOthers) })
    }

    func testShakeToHideRoundTripsAndDefaultsOn() throws {
        let decoded = try XCTUnwrap(SnapConfiguration(json: "{}"))
        XCTAssertTrue(decoded.isShakeToHideEnabled)

        var configuration = SnapConfiguration.default
        configuration.isShakeToHideEnabled = false
        XCTAssertEqual(try XCTUnwrap(SnapConfiguration(json: configuration.json)), configuration)
    }
}
