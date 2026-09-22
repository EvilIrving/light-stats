//
//  SystemWindowTilingTests.swift
//  Light Stats Tests
//
//  The handover that keeps one gesture from having two implementations.
//
//  `reconcile` takes its writer as a parameter precisely so this rule can be tested without writing
//  to the machine's real `com.apple.WindowManager` domain — a test must never change the system
//  settings of the machine it runs on.
//

import XCTest
@testable import Light_Stats

final class SystemWindowTilingTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LightStatsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// Hands every write to a recorder instead of the real preference domain.
    private func recorder() -> (record: (SnapEdgeOwner) -> Void, applied: () -> [SnapEdgeOwner]) {
        var applied: [SnapEdgeOwner] = []
        return ({ applied.append($0) }, { applied })
    }

    // MARK: - The mapping

    /// macOS tiles the sides and the menu bar with one setting each, so an owner that turned off
    /// only one of them would leave the same race at the other edge.
    func testEachOwnerMapsToBothSwitchesAtOnce() {
        let lightStats = SystemWindowTilingSetting.switches(for: .lightStats)
        XCTAssertFalse(lightStats.edgeDrag)
        XCTAssertFalse(lightStats.topEdgeDrag)

        let system = SystemWindowTilingSetting.switches(for: .system)
        XCTAssertTrue(system.edgeDrag)
        XCTAssertTrue(system.topEdgeDrag)
    }

    // MARK: - Applying it once per transition

    func testTheFirstLaunchAfterTheChoiceExistedAppliesIt() throws {
        try requireOwnershipSwitches()
        let spy = recorder()

        SystemWindowTilingSetting.reconcile(owner: .lightStats, defaults: defaults, apply: spy.record)

        XCTAssertEqual(spy.applied(), [.lightStats],
                       "An install that never chose still has to hand the gesture to exactly one side")
        XCTAssertEqual(defaults.string(forKey: SystemWindowTilingSetting.appliedOwnerKey),
                       SnapEdgeOwner.lightStats.rawValue)
    }

    /// The reason this is not applied on every launch: a user who turns the system's switch back on
    /// by hand must keep that setting, and Settings reports the conflict instead of reverting them.
    func testTheSameOwnerIsNeverAppliedTwice() throws {
        try requireOwnershipSwitches()
        let spy = recorder()

        SystemWindowTilingSetting.reconcile(owner: .lightStats, defaults: defaults, apply: spy.record)
        SystemWindowTilingSetting.reconcile(owner: .lightStats, defaults: defaults, apply: spy.record)
        SystemWindowTilingSetting.reconcile(owner: .lightStats, defaults: defaults, apply: spy.record)

        XCTAssertEqual(spy.applied(), [.lightStats])
    }

    func testSwitchingOwnerAppliesTheNewOne() throws {
        try requireOwnershipSwitches()
        let spy = recorder()

        SystemWindowTilingSetting.reconcile(owner: .lightStats, defaults: defaults, apply: spy.record)
        SystemWindowTilingSetting.reconcile(owner: .system, defaults: defaults, apply: spy.record)
        SystemWindowTilingSetting.reconcile(owner: .lightStats, defaults: defaults, apply: spy.record)

        XCTAssertEqual(spy.applied(), [.lightStats, .system, .lightStats])
    }

    /// A value written by a build that no longer exists must not wedge the reconciliation.
    func testAnUnreadableStoredOwnerIsTreatedAsUnapplied() throws {
        try requireOwnershipSwitches()
        defaults.set("somethingElse", forKey: SystemWindowTilingSetting.appliedOwnerKey)
        let spy = recorder()

        SystemWindowTilingSetting.reconcile(owner: .lightStats, defaults: defaults, apply: spy.record)

        XCTAssertEqual(spy.applied(), [.lightStats])
    }

    private func requireOwnershipSwitches() throws {
        guard #available(macOS 15.0, *) else {
            throw XCTSkip("macOS' own drag-to-edge tiling, and therefore the handover, needs macOS 15")
        }
    }
}
