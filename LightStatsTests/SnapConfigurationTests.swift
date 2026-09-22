//
//  SnapConfigurationTests.swift
//  Light Stats Tests
//
//  Persistence and the invariants that keep the settings honest.
//
//  The configuration is one JSON blob in `UserDefaults`, so the decode path has to survive a value
//  written by an older build — otherwise adding one preference wipes every choice the user has
//  made. That is the first test below, and it is the reason `init(from:)` is hand-written.
//

import XCTest
@testable import Light_Stats

final class SnapConfigurationTests: XCTestCase {

    func testDefaultRoundTripsThroughItsJSON() {
        let original = SnapConfiguration.default
        let decoded = SnapConfiguration(json: original.json)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, original)
    }

    func testJSONIsNotGarbage() {
        XCTAssertFalse(SnapConfiguration.default.json.isEmpty)
        XCTAssertNil(SnapConfiguration(json: "not json"))
        XCTAssertNil(SnapConfiguration(json: ""))
    }

    /// A stored value from a build that predates the ownership choice — and that still carries the
    /// gap, which is no longer a preference at all. Both are dropped rather than fatal.
    func testLegacyJSONWithoutTheOwnerDecodesToLightStats() throws {
        let legacy = #"{"margins":{"outer":8,"inner":12}}"#
        let decoded = try XCTUnwrap(SnapConfiguration(json: legacy))

        XCTAssertEqual(decoded.edgeOwner, .lightStats,
                       "An install that never chose an owner keeps the behaviour it had: our engine")
        // Everything else survives with its default rather than being reset to nothing.
        XCTAssertEqual(decoded.zones, SnapZoneConfiguration.default)
        XCTAssertEqual(decoded.island, SnapIslandConfiguration.default)
        XCTAssertTrue(decoded.showsPreview)
        XCTAssertTrue(decoded.honorsRestrictedApps)
        XCTAssertFalse(decoded.shortcuts.isEmpty)
        XCTAssertEqual(decoded.islandPalette, .neutral)
        XCTAssertFalse(decoded.prefersNativeTiling,
                       "The system's commands are only used when macOS owns the gesture")
        XCTAssertTrue(decoded.isDockClickCollapseEnabled,
                       "A new behaviour arrives switched on rather than silently missing from an upgrade")
    }

    func testTheOwnerRoundTrips() throws {
        var configuration = SnapConfiguration.default
        configuration.edgeOwner = .system
        let decoded = try XCTUnwrap(SnapConfiguration(json: configuration.json))
        XCTAssertEqual(decoded.edgeOwner, .system)
    }

    func testAnEmptyObjectDecodesToTheDefaults() throws {
        let decoded = try XCTUnwrap(SnapConfiguration(json: "{}"))
        XCTAssertEqual(decoded, SnapConfiguration.default)
    }

    /// Preview and palette are product defaults — not settings. Older installs may still carry
    /// custom values; normalisation clears them without touching the rest of the blob.
    func testProductFixedPreferencesResetHiddenSettingsOnly() {
        var configuration = SnapConfiguration.default
        configuration.showsPreview = false
        configuration.islandPalette = .vivid
        configuration.isShakeToHideEnabled = false

        let fixed = configuration.withProductFixedPreferences()
        XCTAssertTrue(fixed.showsPreview)
        XCTAssertEqual(fixed.islandPalette, .neutral)
        XCTAssertFalse(fixed.isShakeToHideEnabled)
    }

    // MARK: - Shortcuts

    func testShortcutLookupReturnsAnUnboundPlaceholderForUnknownTargets() {
        let shortcut = SnapConfiguration.default.shortcut(for: .action(.leftThird))
        XCTAssertFalse(shortcut.isBound)
        XCTAssertEqual(shortcut.keyCode, 0)
        XCTAssertEqual(shortcut.target, .action(.leftThird))
    }

    /// A recorded key makes a binding live; there is no separate enable flag to forget to set.
    func testRecordingAKeyIsWhatMakesABindingBound() {
        var configuration = SnapConfiguration.default
        let target = SnapTarget.action(.leftThird)
        configuration.setShortcut(SnapShortcut(target: target, keyCode: 0, modifiers: 0))
        XCTAssertFalse(configuration.shortcut(for: target).isBound)

        var recorded = configuration.shortcut(for: target)
        recorded.keyCode = WindowSnapKeyCode.leftArrow
        recorded.modifiers = SnapConfiguration.defaultModifiers
        configuration.setShortcut(recorded)
        XCTAssertTrue(configuration.shortcut(for: target).isBound)
    }

    func testSetShortcutReplacesRatherThanDuplicates() {
        var configuration = SnapConfiguration.default
        configuration.setShortcut(SnapShortcut(action: .leftHalf, keyCode: 7, modifiers: 1))
        let matches = configuration.shortcuts.filter { $0.target == .action(.leftHalf) }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.keyCode, 7)
    }

    func testSetShortcutAppendsANewBinding() {
        var configuration = SnapConfiguration.default
        let before = configuration.shortcuts.count
        configuration.setShortcut(SnapShortcut(action: .rightThird, keyCode: 9, modifiers: 2))
        XCTAssertEqual(configuration.shortcuts.count, before + 1)
    }

    func testRemoveShortcutDropsTheBinding() {
        var configuration = SnapConfiguration.default
        configuration.removeShortcut(for: .action(.leftHalf))
        XCTAssertFalse(configuration.shortcuts.contains { $0.target == .action(.leftHalf) })
        XCTAssertFalse(configuration.shortcut(for: .action(.leftHalf)).isBound)
    }

    func testDefaultShortcutSetCoversTheOriginalSixBindings() {
        let targets = Set(SnapConfiguration.default.shortcuts.map(\.target))
        for action: WindowSnapAction in [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .center] {
            XCTAssertTrue(targets.contains(.action(action)), "\(action)")
        }
    }

    func testShortcutHotKeyCarriesTheTarget() {
        let shortcut = SnapShortcut(action: .topLeft, keyCode: 12, modifiers: 3)
        XCTAssertEqual(shortcut.hotKey.keyCode, 12)
        XCTAssertEqual(shortcut.hotKey.modifiers, 3)
        XCTAssertEqual(shortcut.hotKey.target, .action(.topLeft))
    }

    // MARK: - Layouts and pruning

    func testIslandLayoutsResolveInTheConfiguredOrder() {
        var configuration = SnapConfiguration.default
        configuration.islandLayoutIDs = [
            SnapLayoutCatalog.ninthsID,
            SnapLayoutCatalog.halvesID,
            "missing"
        ]
        XCTAssertEqual(
            configuration.islandLayouts.map(\.id),
            [SnapLayoutCatalog.ninthsID, SnapLayoutCatalog.halvesID]
        )
    }

    func testCustomLayoutsAreReachableById() {
        var configuration = SnapConfiguration.default
        let custom = SnapLayout(
            id: "custom-1",
            title: "Wide",
            isBuiltIn: false,
            segments: [SnapSegment(id: "s", title: "Wide", rect: SnapNormalizedRect(x: 0, y: 0, width: 0.75, height: 1))]
        )
        configuration.customLayouts = [custom]
        XCTAssertEqual(configuration.layout(id: "custom-1"), custom)
        XCTAssertEqual(configuration.allLayouts.count, SnapLayoutCatalog.builtIn.count + 1)
    }

    func testPruningDropsLayoutsThatNoLongerExist() {
        var configuration = SnapConfiguration.default
        configuration.islandLayoutIDs = ["custom-gone", SnapLayoutCatalog.halvesID]
        configuration.pruneDanglingReferences()
        XCTAssertEqual(configuration.islandLayoutIDs, [SnapLayoutCatalog.halvesID])
    }

    func testPruningRefillsTheIslandWhenEverythingWasRemoved() {
        var configuration = SnapConfiguration.default
        configuration.customLayouts = []
        configuration.islandLayoutIDs = ["custom-gone"]
        configuration.pruneDanglingReferences()
        XCTAssertFalse(configuration.islandLayoutIDs.isEmpty)
        XCTAssertTrue(configuration.islandLayouts.allSatisfy { $0.isUsable })
    }

    func testPruningDropsShortcutsWhoseGeometryIsGone() {
        var configuration = SnapConfiguration.default
        let orphan = SnapNormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        configuration.setShortcut(SnapShortcut(target: .region(orphan), keyCode: 4, modifiers: 5))
        configuration.pruneDanglingReferences()
        XCTAssertFalse(configuration.shortcuts.contains { $0.target == .region(orphan) })
    }

    func testPruningKeepsShortcutsThatStillResolve() {
        var configuration = SnapConfiguration.default
        let kept = SnapLayoutCatalog.halves.segments[0].rect
        configuration.setShortcut(SnapShortcut(target: .region(kept), keyCode: 4, modifiers: 5))
        configuration.pruneDanglingReferences()
        XCTAssertTrue(configuration.shortcuts.contains { $0.target == .region(kept) })
    }

    func testLineageDefaultsThatArePrunedOnDecode() throws {
        // A stored config whose island points at a layout that no longer exists.
        let stored = #"{"islandLayoutIDs":["built-in-halves","does-not-exist"]}"#
        let decoded = try XCTUnwrap(SnapConfiguration(json: stored))
        XCTAssertEqual(decoded.islandLayoutIDs, [SnapLayoutCatalog.halvesID])
    }

    // MARK: - Derived

    func testExclusionSetMirrorsTheList() {
        var configuration = SnapConfiguration.default
        configuration.exclusions = ["a", "b"]
        XCTAssertEqual(configuration.exclusionSet, ["a", "b"])
    }

    /// The island cannot be the top-edge answer with nothing to show, so the pipeline falls back
    /// to filling the screen rather than making the gesture do nothing.
    func testTopEdgeFallsBackToMaximizeWhenThereAreNoLayouts() {
        var configuration = SnapConfiguration.default
        configuration.islandLayoutIDs = []
        configuration.customLayouts = []
        XCTAssertTrue(configuration.islandLayouts.isEmpty)
        XCTAssertEqual(configuration.effectiveZones.topEdgeMode, .maximize)
        // The stored preference is untouched, so restoring a layout restores the island.
        XCTAssertEqual(configuration.zones.topEdgeMode, .island)
    }

    func testEffectiveZonesAreUnchangedWhenTheIslandHasLayouts() {
        let configuration = SnapConfiguration.default
        XCTAssertEqual(configuration.effectiveZones.topEdgeMode, .island)
    }

    func testDragSnappingIsActiveWhenAnyZoneIsOn() {
        XCTAssertTrue(SnapConfiguration.default.isDragSnappingActive)
        var configuration = SnapConfiguration.default
        configuration.zones = .disabled
        configuration.isShakeToHideEnabled = false
        XCTAssertFalse(configuration.isDragSnappingActive)
    }

    // MARK: - Ownership

    /// The product default is our own engine, which is also what every existing install decodes to.
    func testLightStatsOwnsTheGestureByDefault() {
        XCTAssertEqual(SnapConfiguration.default.edgeOwner, .lightStats)
    }

    /// With macOS owning the gesture the zones must arm nothing, or the system and our engine would
    /// both act on the same mouse-up — the exact race the ownership choice exists to remove.
    func testSystemOwnershipDisablesEveryZoneWithoutErasure() {
        var configuration = SnapConfiguration.default
        configuration.edgeOwner = .system

        XCTAssertEqual(configuration.effectiveZones, .disabled)
        let screen = SnapScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 850))
        XCTAssertNil(SnapZonePolicy.result(pointer: CGPoint(x: 1, y: 400), screen: screen,
                                           configuration: configuration.effectiveZones).target)
        XCTAssertFalse(configuration.effectiveZones.isActive)
        // The stored choices are untouched, so switching back restores the user's own zones.
        XCTAssertEqual(configuration.zones, SnapZoneConfiguration.default)
        XCTAssertEqual(SnapConfiguration.default.zones, .default)
    }

    /// Shake-to-hide is a different gesture that shares the monitor, so it keeps the monitor alive
    /// even while macOS owns the edges — and takes it down with it when it is off too.
    func testShakeToHideDecidesTheMonitorOnceMacOSOwnsTheEdges() {
        var configuration = SnapConfiguration.default
        configuration.edgeOwner = .system
        XCTAssertTrue(configuration.isDragSnappingActive)
        configuration.isShakeToHideEnabled = false
        XCTAssertFalse(configuration.isDragSnappingActive)
    }

    /// "Let macOS place the window" was a second switch asking the same question as the owner, and
    /// on a drag it could never apply — a zone resolves to a `.region` target, which the system has
    /// no command for. It is derived now, so one choice governs both paths.
    func testTheSystemOwnerIsAlsoWhatRoutesPlacementThroughSystemCommands() {
        XCTAssertFalse(SnapConfiguration.default.prefersNativeTiling)

        var configuration = SnapConfiguration.default
        configuration.edgeOwner = .system
        XCTAssertTrue(configuration.prefersNativeTiling)

        configuration.edgeOwner = .lightStats
        XCTAssertFalse(configuration.prefersNativeTiling)
    }
}

final class SnapTargetCodingTests: XCTestCase {

    /// The shortcut store persists targets, so their wire format is a contract. The synthesized
    /// shape for an enum with associated values is positional; this pins the named one instead.
    func testActionTargetRoundTrips() throws {
        let target = SnapTarget.action(.leftTwoThirds)
        let data = try JSONEncoder().encode(target)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("leftTwoThirds"), json)
        XCTAssertEqual(try JSONDecoder().decode(SnapTarget.self, from: data), target)
    }

    func testRegionTargetRoundTrips() throws {
        let target = SnapTarget.region(SnapNormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5))
        let data = try JSONEncoder().encode(target)
        XCTAssertEqual(try JSONDecoder().decode(SnapTarget.self, from: data), target)
    }

    func testActionTargetsAreDistinctFromEqualLookingRegions() {
        XCTAssertNotEqual(SnapTarget.action(.leftHalf), SnapTarget.region(.leftHalf))
        XCTAssertEqual(SnapTarget.action(.leftHalf).action, .leftHalf)
        XCTAssertNil(SnapTarget.action(.leftHalf).region)
        XCTAssertEqual(SnapTarget.region(.leftHalf).region, .leftHalf)
        XCTAssertNil(SnapTarget.region(.leftHalf).action)
    }

    func testDiagnosticNameIsStableAndReadable() {
        XCTAssertEqual(SnapTarget.action(.topLeft).diagnosticName, "topLeft")
        XCTAssertEqual(
            SnapTarget.region(SnapNormalizedRect(x: 0, y: 0, width: 0.5, height: 1)).diagnosticName,
            "region(0.000,0.000,0.500,1.000)"
        )
    }
}
