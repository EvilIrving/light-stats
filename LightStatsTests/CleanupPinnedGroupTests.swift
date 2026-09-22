//
//  CleanupPinnedGroupTests.swift
//  Light Stats Tests
//
//  Pure rules for the Cleanup pinned batch-quit group. No live processes.
//

import AppKit
import XCTest
@testable import Light_Stats

final class CleanupPinnedGroupTests: XCTestCase {

    private let icon = NSImage()

    func testMemberKeyPrefersBundleIdOverPath() {
        XCTAssertEqual(
            CleanupPinnedGroupPolicy.memberKey(
                bundleIdentifier: "com.example.app",
                bundlePath: "/Applications/Example.app"
            ),
            "com.example.app"
        )
    }

    func testMemberKeyFallsBackToBundlePath() {
        XCTAssertEqual(
            CleanupPinnedGroupPolicy.memberKey(
                bundleIdentifier: nil,
                bundlePath: "/Applications/Example.app"
            ),
            "/Applications/Example.app"
        )
        XCTAssertEqual(
            CleanupPinnedGroupPolicy.memberKey(
                bundleIdentifier: "",
                bundlePath: "/Applications/Example.app"
            ),
            "/Applications/Example.app"
        )
    }

    func testMemberKeyNilWhenNeitherPresent() {
        XCTAssertNil(CleanupPinnedGroupPolicy.memberKey(bundleIdentifier: nil, bundlePath: nil))
        XCTAssertNil(CleanupPinnedGroupPolicy.memberKey(bundleIdentifier: "", bundlePath: ""))
    }

    func testBackgroundAndNonTerminableRowsCannotPin() {
        let background = makeApp(
            id: AppGroup.backgroundGroupId,
            name: "Background",
            terminable: false,
            bundleId: nil
        )
        let pinnedStub = makeApp(
            id: AppGroup.pinnedGroupId,
            name: "Pinned",
            terminable: false,
            bundleId: "pinned"
        )
        let locked = makeApp(id: 42, name: "Locked", terminable: false, bundleId: "com.locked")
        XCTAssertFalse(CleanupPinnedGroupPolicy.canPin(background))
        XCTAssertFalse(CleanupPinnedGroupPolicy.canPin(pinnedStub))
        XCTAssertFalse(CleanupPinnedGroupPolicy.canPin(locked))
    }

    func testTerminableAppCanPin() {
        let app = makeApp(id: 7, name: "Safari", terminable: true, bundleId: "com.apple.Safari")
        XCTAssertTrue(CleanupPinnedGroupPolicy.canPin(app))
        XCTAssertEqual(CleanupPinnedGroupPolicy.memberKey(for: app), "com.apple.Safari")
    }

    func testDropPayloadMustMatchRunningEligibleApp() {
        let safari = makeApp(id: 1, name: "Safari", terminable: true, bundleId: "com.apple.Safari")
        let chrome = makeApp(id: 2, name: "Chrome", terminable: true, bundleId: "com.google.Chrome")
        XCTAssertEqual(
            CleanupPinnedGroupPolicy.validatedDropKey("com.apple.Safari", among: [safari, chrome]),
            "com.apple.Safari"
        )
        XCTAssertNil(
            CleanupPinnedGroupPolicy.validatedDropKey("com.missing.app", among: [safari, chrome]),
            "不属于当前运行列表的 payload 必须忽略"
        )
        XCTAssertNil(CleanupPinnedGroupPolicy.validatedDropKey("", among: [safari]))
    }

    func testInsertIsIdempotent() {
        let first = CleanupPinnedGroupPolicy.inserting("a", into: [])
        XCTAssertEqual(first.keys, ["a"])
        XCTAssertTrue(first.changed)
        let second = CleanupPinnedGroupPolicy.inserting("a", into: first.keys)
        XCTAssertEqual(second.keys, ["a"])
        XCTAssertFalse(second.changed, "重复入组是幂等 no-op")
    }

    func testPartitionMovesOnlyPinnedRunningMembers() {
        let safari = makeApp(id: 1, name: "Safari", terminable: true, bundleId: "com.apple.Safari")
        let mail = makeApp(id: 2, name: "Mail", terminable: true, bundleId: "com.apple.mail")
        let background = makeApp(
            id: AppGroup.backgroundGroupId,
            name: "Background",
            terminable: false,
            bundleId: nil
        )
        let (top, pinned) = CleanupPinnedGroupPolicy.partition(
            [safari, mail, background],
            pinnedKeys: ["com.apple.Safari", "com.not.running"]
        )
        XCTAssertEqual(top.map(\.id), [mail.id, AppGroup.backgroundGroupId])
        XCTAssertEqual(pinned.map(\.bundleIdentifier), ["com.apple.Safari"])
    }

    func testPartitionPreservesPinnedKeysForAppsNotCurrentlyRunning() {
        // "com.not.running" stays in the persisted key set (caller concern);
        // partition only reports currently running members.
        let mail = makeApp(id: 2, name: "Mail", terminable: true, bundleId: "com.apple.mail")
        let (_, pinned) = CleanupPinnedGroupPolicy.partition(
            [mail],
            pinnedKeys: ["com.apple.Safari", "com.apple.mail"]
        )
        XCTAssertEqual(pinned.map(\.bundleIdentifier), ["com.apple.mail"])
        XCTAssertEqual(
            CleanupPinnedGroupPolicy.runningMemberCount(pinnedMembers: pinned),
            1,
            "计数只统计当前在运行的分组成员"
        )
    }

    func testBatchPlanSkipsNonTerminableAndKeepsOrder() {
        let a = makeApp(id: 1, name: "A", terminable: true, bundleId: "a")
        let b = makeApp(id: 2, name: "B", terminable: false, bundleId: "b")
        let c = makeApp(id: 3, name: "C", terminable: true, bundleId: "c")
        let plan = CleanupPinnedGroupPolicy.batchTerminationPlan(from: [a, b, c])
        XCTAssertEqual(plan.map(\.id), [1, 3])
    }

    private func makeApp(
        id: pid_t,
        name: String,
        terminable: Bool,
        bundleId: String?
    ) -> AppGroup {
        AppGroup(
            id: id,
            name: name,
            icon: icon,
            totalMemoryBytes: 1_024,
            processCount: 1,
            allPids: id > 0 ? [id] : [],
            terminablePids: terminable && id > 0 ? [id] : [],
            isTerminable: terminable,
            bundleIdentifier: bundleId,
            bundlePath: bundleId.map { "/Applications/\($0).app" },
            execPath: nil
        )
    }
}
