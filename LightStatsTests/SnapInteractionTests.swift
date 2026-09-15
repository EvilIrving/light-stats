//
//  SnapInteractionTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

final class SnapInteractionTests: XCTestCase {
    func testPreviewFocusUsesIdentityBeforeSharedMaximizedGeometry() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let candidates = [
            WindowPreviewMatchPolicy.Candidate(windowID: nil, title: "A", frame: frame),
            WindowPreviewMatchPolicy.Candidate(windowID: nil, title: "B", frame: frame)
        ]
        XCTAssertEqual(WindowPreviewMatchPolicy.index(windowID: 42, title: "B", frame: frame, candidates: candidates), 1)
        XCTAssertNil(WindowPreviewMatchPolicy.index(windowID: 42, title: nil, frame: frame, candidates: candidates),
                     "Two maximized windows are not interchangeable")
        let identified = [
            WindowPreviewMatchPolicy.Candidate(windowID: 42, title: "", frame: nil),
            WindowPreviewMatchPolicy.Candidate(windowID: 43, title: "B", frame: frame)
        ]
        XCTAssertEqual(WindowPreviewMatchPolicy.index(windowID: 42, title: "B", frame: frame, candidates: identified), 0)
    }

    func testPreviewInventoryKeepsRealWindowsAndRejectsWindowServerFurniture() {
        var entry = WindowServerInventory.Entry(windowID: 1, processID: 2,
                                                bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                                                title: nil, layer: 0, isOnScreen: false, ownerName: nil)
        XCTAssertTrue(WindowPreviewCatalog.isPreviewable(entry), "Offscreen windows remain available for switching")
        entry.layer = 25
        XCTAssertFalse(WindowPreviewCatalog.isPreviewable(entry), "Menu bars and overlays are not application windows")
        entry.layer = 0
        entry.bounds.size = CGSize(width: 10, height: 10)
        XCTAssertFalse(WindowPreviewCatalog.isPreviewable(entry))
    }

    func testLegacyNarrowTriggerBandsAreUpgradedForAnApproachableEdgeGesture() {
        var configuration = SnapConfiguration.default
        configuration.zones.edgeThreshold = 12
        XCTAssertEqual(configuration.effectiveZones.edgeThreshold, 24)
        let screen = SnapScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 850))
        let zone = SnapZonePolicy.result(pointer: CGPoint(x: 20, y: 400), screen: screen,
                                         configuration: configuration.effectiveZones)
        XCTAssertEqual(zone.target, .region(.leftHalf), "The pointer need not touch the last few screen pixels to arm a split")
    }

    func testReassigningAKeyCombinationMovesItsBindingInsteadOfFailingRegistration() {
        var configuration = SnapConfiguration.default
        configuration.setShortcut(SnapShortcut(action: .rightThird, keyCode: WindowSnapKeyCode.leftArrow,
                                               modifiers: SnapConfiguration.defaultModifiers))
        XCTAssertFalse(configuration.shortcut(for: .action(.leftHalf)).isBound)
        XCTAssertTrue(configuration.shortcut(for: .action(.rightThird)).isBound)
        XCTAssertEqual(configuration.shortcuts.filter {
            $0.keyCode == WindowSnapKeyCode.leftArrow && $0.modifiers == SnapConfiguration.defaultModifiers
        }.count, 1)
    }

    func testQuantizedTerminalSizesStayAlignedToTheOuterTileEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let target = CGRect(x: 720, y: 450, width: 720, height: 450)
        let frame = WindowPlacementAdjustment.frame(target: target, acceptedSize: CGSize(width: 712, height: 442),
                                                    screen: screen, isResizable: true)
        XCTAssertEqual(frame.maxX, target.maxX)
        XCTAssertEqual(frame.maxY, target.maxY)
        let fixed = WindowPlacementAdjustment.frame(target: target, acceptedSize: CGSize(width: 300, height: 200),
                                                    screen: screen, isResizable: false)
        XCTAssertEqual(fixed.midX, target.midX)
        XCTAssertEqual(fixed.midY, target.midY)
    }

    func testCloseAndQuitAreExplicitUnboundCommandsWithoutPlacementGeometry() {
        for action in [WindowSnapAction.closeWindow, .quitApplication] {
            XCTAssertTrue(action.isWindowControl)
            XCTAssertNil(WindowSnapGeometry.normalizedRect(for: action))
            XCTAssertFalse(SnapConfiguration.default.shortcut(for: .action(action)).isBound,
                           "Closing windows and quitting apps must require a deliberately recorded shortcut")
        }
    }

    func testManyPinnedLayoutsWrapWithoutOverlappingTheSegmentGrid() {
        let layouts = (0..<20).map { index in
            SnapLayout(id: "layout-\(index)", title: "", isBuiltIn: false, segments: SnapLayoutCatalog.halves.segments)
        }
        let panel = CGRect(x: 0, y: 0, width: 420, height: 260)
        let frames = SnapIslandLayout.layoutFrames(layouts: layouts, panel: panel)
        XCTAssertEqual(frames.count, layouts.count)
        for entry in frames {
            XCTAssertGreaterThan(entry.frame.width, 20)
            XCTAssertLessThanOrEqual(entry.frame.maxY, panel.maxY)
            let tiles = SnapIslandLayout.tiles(layouts: layouts, panel: panel, margins: .zero)
                .filter { $0.layoutID == entry.id }
            XCTAssertFalse(tiles.isEmpty)
        }
    }

    func testDockPreviewSurvivesTheGapButEventuallyDismisses() {
        var retention = DockPreviewRetention()
        retention.visit(at: 10)
        XCTAssertFalse(retention.shouldDismiss(at: 10.15), "Crossing from the Dock to its preview must not dismiss it")
        XCTAssertTrue(retention.shouldDismiss(at: 10.3))
        retention.visit(at: 10.2)
        XCTAssertFalse(retention.shouldDismiss(at: 10.3), "Arriving inside the panel renews retention")
        retention.reset()
        XCTAssertTrue(retention.shouldDismiss(at: 10.3))
    }

    func testMinimizedAndFullscreenWindowsRemainReachableInPreviews() {
        let candidate = SnapWindowCandidate(
            role: "AXWindow", subrole: "AXStandardWindow", title: "Editor",
            bundleIdentifier: "com.jetbrains.idea", executableName: "idea",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800), isMinimized: true, isFullScreen: true
        )
        XCTAssertTrue(SnapWindowEligibility.isPreviewable(candidate, userExclusions: []),
                      "A window that cannot be resized can still be selected in the switcher")
        XCTAssertFalse(SnapWindowEligibility.isEligible(candidate, userExclusions: [], honorsRestrictedList: true))
        XCTAssertFalse(SnapWindowEligibility.isPreviewable(candidate, userExclusions: ["com.jetbrains.idea"]))
    }

    func testAnIslandDropBelowTheTopBandStillCommitsTheSelectedTile() {
        let screen = SnapScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 850))
        let point = CGPoint(x: 700, y: 110)
        let zone = SnapZonePolicy.result(pointer: point, screen: screen, configuration: .default)
        XCTAssertFalse(zone.isIslandActive)
        XCTAssertEqual(zone.screen, screen, "Leaving the trigger band must retain the display for the drop")
        XCTAssertEqual(SnapDropPolicy.target(islandOwnsDrop: true, islandTarget: .region(.leftHalf), edgeTarget: zone.target),
                       .region(.leftHalf))
    }

    func testDroppingInAnIslandGapNeverFallsThroughToMaximize() {
        XCTAssertNil(SnapDropPolicy.target(islandOwnsDrop: true, islandTarget: nil, edgeTarget: .region(.full)))
        XCTAssertEqual(SnapDropPolicy.target(islandOwnsDrop: false, islandTarget: nil, edgeTarget: .region(.full)), .region(.full))
    }

    func testDisablingEdgesDisablesTheBottomEdgeEvenWhenTheIslandIsOn() {
        var configuration = SnapZoneConfiguration.default
        configuration.edgesEnabled = false
        configuration.cornersEnabled = false
        let screen = SnapScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertNil(SnapZonePolicy.result(pointer: CGPoint(x: 720, y: 899), screen: screen, configuration: configuration).target)
    }

    func testShakeOnlyConfigurationStillRunsTheDragMonitor() {
        var configuration = SnapConfiguration.default
        configuration.zones = .disabled
        XCTAssertTrue(configuration.isDragSnappingActive)
        configuration.isShakeToHideEnabled = false
        XCTAssertFalse(configuration.isDragSnappingActive)
    }

    func testAllLayoutsUnpinnedSurvivesRestart() throws {
        var configuration = SnapConfiguration.default
        configuration.islandLayoutIDs = []
        let decoded = try XCTUnwrap(SnapConfiguration(json: configuration.json))
        XCTAssertTrue(decoded.islandLayoutIDs.isEmpty, "Unpinning every layout is an intentional preference")
        XCTAssertEqual(decoded.effectiveZones.topEdgeMode, .maximize)
    }

    func testEveryPreviewIsAUniformProjectionOfTheActualPlacement() {
        let source = CGSize(width: 1728, height: 1080)
        let bounds = CGRect(x: 18, y: 44, width: 312, height: 130)
        let margins = SnapMargins(outer: 30, inner: 24)
        let viewport = SnapLayoutProjection.viewport(in: bounds, sourceSize: source)
        let scale = viewport.width / source.width
        for layout in SnapLayoutCatalog.builtIn {
            for segment in layout.segments {
                let actual = SnapGridGeometry.frame(for: segment.rect, in: CGRect(origin: .zero, size: source), margins: margins)
                let preview = SnapLayoutProjection.frame(for: segment.rect, in: bounds, margins: margins, sourceSize: source)
                XCTAssertEqual((preview.minX - viewport.minX) / scale, actual.minX, accuracy: 0.0001)
                XCTAssertEqual((preview.minY - viewport.minY) / scale, actual.minY, accuracy: 0.0001)
                XCTAssertEqual(preview.width / scale, actual.width, accuracy: 0.0001)
                XCTAssertEqual(preview.height / scale, actual.height, accuracy: 0.0001)
            }
        }
    }

    func testIslandDrawingAndHitTestsShareTheProjectedGridOnPortraitDisplays() {
        let size = CGSize(width: 900, height: 1600)
        let panel = CGRect(x: 0, y: 0, width: 540, height: 160)
        for layout in SnapLayoutCatalog.builtIn {
            let frames = SnapIslandLayout.tiles(layouts: [layout], panel: panel, margins: .zero, sourceSize: size)
            for entry in frames {
                let point = CGPoint(x: entry.frame.midX, y: entry.frame.midY)
                XCTAssertEqual(SnapIslandLayout.hit(at: point, layouts: [layout], panel: panel,
                                                    margins: .zero, sourceSize: size)?.segment.id, entry.segment.id)
            }
        }
    }

    func testTinyIslandGeometryDoesNotInvertOrLeaveTheDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 18, height: 20)
        for state in [SnapIslandState.collapsed, .open] {
            let frame = SnapIslandPolicy.frame(for: state, in: screen, configuration: .default)
            XCTAssertGreaterThanOrEqual(frame.width, 0)
            XCTAssertLessThanOrEqual(frame.height, screen.height)
        }
    }

    func testMultiRegionLayoutEditingRejectsOverlapAndSupportsUndo() {
        var draft = SnapLayoutDraft()
        XCTAssertTrue(draft.put(.leftHalf))
        XCTAssertTrue(draft.put(.topRightQuarter))
        XCTAssertTrue(draft.put(.bottomRightQuarter))
        XCTAssertEqual(draft.segments.count, 3)
        XCTAssertFalse(draft.put(.full), "Drawing across existing tiles must not silently overlap them")
        draft.removeSelected()
        XCTAssertEqual(draft.segments.count, 2)
        draft.undo()
        XCTAssertEqual(draft.segments.count, 3)
        XCTAssertFalse(draft.put(SnapNormalizedRect(x: .nan, y: 0, width: 1, height: 1)))
    }

    func testMoveAndResizeClampAtScreenEdges() {
        let moved = SnapLayoutDraft.moved(.topLeftQuarter, columns: 12, rows: -12)
        XCTAssertEqual(moved, .topRightQuarter)
        let expanded = SnapLayoutDraft.resized(.bottomRightQuarter, columns: 12, rows: 12)
        XCTAssertEqual(expanded, .bottomRightQuarter)
        let shrunk = SnapLayoutDraft.resized(.leftHalf, columns: -12, rows: -12)
        XCTAssertEqual(shrunk.width, 0.125)
        XCTAssertEqual(shrunk.height, 0.125)
    }

    func testEditingARegionKeepsItsIdentityAndRejectsCollisions() throws {
        var draft = SnapLayoutDraft()
        draft.put(.leftHalf)
        let leftID = try XCTUnwrap(draft.selectedID)
        draft.put(.rightHalf)
        XCTAssertFalse(draft.put(.full, replacing: leftID))
        XCTAssertTrue(draft.put(.topLeftQuarter, replacing: leftID))
        XCTAssertEqual(draft.segments.first?.id, leftID)
        XCTAssertEqual(draft.segments.count, 2)
    }

    func testSaveEditReorderAndRestartPreserveTheWholeLayout() throws {
        var configuration = SnapConfiguration.default
        var draft = SnapLayoutDraft()
        draft.put(.leftHalf)
        draft.put(.topRightQuarter)
        draft.put(.bottomRightQuarter)
        var layout = SnapLayout(id: "custom-test", title: "Work", isBuiltIn: false, segments: draft.segments)
        SnapLayoutEditing.save(layout, in: &configuration)
        layout.title = "Edited"
        SnapLayoutEditing.save(layout, in: &configuration)
        SnapLayoutEditing.move(layout.id, before: SnapLayoutCatalog.halvesID, in: &configuration)
        let decoded = try XCTUnwrap(SnapConfiguration(json: configuration.json))
        XCTAssertEqual(decoded.customLayouts.count, 1)
        XCTAssertEqual(decoded.customLayouts.first, layout)
        XCTAssertEqual(decoded.islandLayouts.first?.id, layout.id)
    }

    func testSavedPositionsHaveACreationPathAndDoNotDuplicate() throws {
        var configuration = SnapConfiguration.default
        SnapLayoutEditing.savePosition(.leftHalf, title: "Left", in: &configuration)
        SnapLayoutEditing.savePosition(.leftHalf, title: "Again", in: &configuration)
        XCTAssertEqual(configuration.savedPlacements.count, 1)
        let decoded = try XCTUnwrap(SnapConfiguration(json: configuration.json))
        XCTAssertEqual(decoded.savedPlacements.first?.rect, .leftHalf)
        let id = try XCTUnwrap(configuration.savedPlacements.first?.id)
        configuration.setShortcut(SnapShortcut(target: .region(.leftHalf), keyCode: 8, modifiers: SnapConfiguration.defaultModifiers))
        SnapLayoutEditing.removePosition(id, in: &configuration)
        XCTAssertTrue(configuration.savedPlacements.isEmpty)
        XCTAssertTrue(configuration.shortcut(for: .region(.leftHalf)).isBound,
                      "Deleting a saved position must retain a shortcut still used by a layout")
    }
}
