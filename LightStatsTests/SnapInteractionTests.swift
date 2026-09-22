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

    func testAHiddenWindowTabIsNeverResolvedToTheVisibleTabSharingItsFrame() {
        // Fork, measured on this machine: three repository windows, one AXWindow. Every tab reports
        // the frame of the tab that is showing, so a geometric match hands the click the window the
        // user is *not* asking for — which is how a preview card came to do nothing visible.
        let showing = CGRect(x: 399, y: 30, width: 1774, height: 1334)
        let current = [WindowPreviewMatchPolicy.Candidate(windowID: nil, title: "swift-between-us", frame: showing)]
        XCTAssertNil(
            WindowPreviewMatchPolicy.index(windowID: 43064, title: "swift-light-stats", frame: showing, candidates: current),
            "A candidate that names itself differently is a different window, however equal the frames are"
        )
        XCTAssertNil(
            WindowPreviewMatchPolicy.index(
                windowID: 43066,
                title: "go-magic",
                frame: CGRect(x: 1039, y: 30, width: 1774, height: 1334),
                candidates: current
            )
        )
        let unnamed = [WindowPreviewMatchPolicy.Candidate(windowID: nil, title: "", frame: showing)]
        XCTAssertEqual(
            WindowPreviewMatchPolicy.index(windowID: 43064, title: "swift-light-stats", frame: showing, candidates: unnamed),
            0,
            "A candidate that cannot name itself is still matched by the frame it shares with the window"
        )
    }

    func testOnlyTheTabThatNamesTheWindowIsSwitchedTo() {
        let tabs = ["swift-light-stats", "swift-between-us", "go-magic"]
        XCTAssertEqual(WindowPreviewMatchPolicy.tabIndex(windowTitle: "go-magic", tabTitles: tabs), 2)
        XCTAssertNil(WindowPreviewMatchPolicy.tabIndex(windowTitle: "somewhere-else", tabTitles: tabs),
                     "A window with no tab of its own must not switch the user to another document")
        XCTAssertNil(WindowPreviewMatchPolicy.tabIndex(windowTitle: "", tabTitles: tabs))
        XCTAssertNil(WindowPreviewMatchPolicy.tabIndex(windowTitle: "untitled", tabTitles: ["untitled", "untitled"]),
                     "Two tabs under one title cannot be told apart")
    }

    func testPreviewInventoryKeepsRealWindowsAndRejectsWindowServerFurniture() {
        var entry = WindowServerInventory.Entry(windowID: 1, processID: 2,
                                                bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                                                title: nil, layer: 0, alpha: 1, isOnScreen: false, ownerName: nil)
        XCTAssertTrue(WindowPreviewCatalog.isPreviewable(entry), "Offscreen windows remain available for switching")
        entry.layer = 25
        XCTAssertFalse(WindowPreviewCatalog.isPreviewable(entry), "Menu bars and overlays are not application windows")
        entry.layer = 0
        entry.bounds.size = CGSize(width: 10, height: 10)
        XCTAssertFalse(WindowPreviewCatalog.isPreviewable(entry))
        entry.bounds.size = CGSize(width: 800, height: 600)
        entry.alpha = 0
        XCTAssertFalse(WindowPreviewCatalog.isPreviewable(entry), "A fully transparent window is not a window anyone can see")
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

    func testTheDragMonitorNeverHitTestsOneOfOurOwnWindows() {
        let own = WindowServerInventory.Entry(
            windowID: 1, processID: 42, bounds: CGRect(x: 100, y: 100, width: 200, height: 200),
            title: "popover", layer: 25, alpha: 1, isOnScreen: true, ownerName: "Light Stats"
        )
        let other = WindowServerInventory.Entry(
            windowID: 2, processID: 99, bounds: CGRect(x: 0, y: 0, width: 900, height: 700),
            title: "Editor", layer: 0, alpha: 1, isOnScreen: true, ownerName: "Editor"
        )
        XCTAssertTrue(OwnSurfaceHitTest.isOwnWindowOnTop(
            at: CGPoint(x: 150, y: 150), in: [own, other], processID: 42
        ), "A hit test over our own popover runs AppKit's Accessibility code on the AX queue")
        XCTAssertFalse(OwnSurfaceHitTest.isOwnWindowOnTop(
            at: CGPoint(x: 150, y: 150), in: [other, own], processID: 42
        ), "Another app's window in front of ours is still snap material")
        XCTAssertFalse(OwnSurfaceHitTest.isOwnWindowOnTop(
            at: CGPoint(x: 800, y: 600), in: [own], processID: 42
        ), "A point outside every listed window belongs to no one")

        var invisible = own
        invisible.alpha = 0
        XCTAssertFalse(OwnSurfaceHitTest.isOwnWindowOnTop(
            at: CGPoint(x: 150, y: 150), in: [invisible, other], processID: 42
        ), "A window nobody can see cannot be what the pointer hit")
    }

    func testTheMenuBarBandIsNeverHitTested() {
        let screen = SnapScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 850)
        )
        XCTAssertTrue(OwnSurfaceHitTest.isInMenuBarBand(CGPoint(x: 700, y: 12), screen: screen),
                      "Status items live in the band, and a same-process hit test on one traps")
        XCTAssertTrue(OwnSurfaceHitTest.isInMenuBarBand(CGPoint(x: 700, y: 0), screen: screen))
        XCTAssertFalse(OwnSurfaceHitTest.isInMenuBarBand(CGPoint(x: 700, y: 25), screen: screen),
                       "The first row of the desktop is window territory again")
        XCTAssertFalse(OwnSurfaceHitTest.isInMenuBarBand(CGPoint(x: 700, y: 500), screen: screen))
        XCTAssertFalse(OwnSurfaceHitTest.isInMenuBarBand(
            CGPoint(x: 700, y: 0),
            screen: SnapScreenGeometry(frame: CGRect(x: -1440, y: -900, width: 1440, height: 900),
                                       visibleFrame: CGRect(x: -1440, y: -900, width: 1440, height: 900))
        ), "A display without a menu bar has no band to exclude")
    }

    func testTheSimulatedDesktopIsDrawnAtTheReferenceScreenShape() {
        XCTAssertEqual(SnapLayoutProjection.referenceAspect, 1440.0 / 900.0, accuracy: 0.0001,
                       "A settings-pane-shaped preview is a shape no display has")
        let bounds = CGRect(x: 0, y: 0, width: 416, height: 416 / SnapLayoutProjection.referenceAspect)
        let viewport = SnapLayoutProjection.viewport(in: bounds, sourceSize: SnapLayoutProjection.referenceSize)
        XCTAssertEqual(viewport.width, bounds.width, accuracy: 0.0001,
                       "The desktop box must be the projection viewport itself, with no letterbox inside it")
        XCTAssertEqual(viewport.height, bounds.height, accuracy: 0.0001)
        XCTAssertEqual(viewport.midX, bounds.midX, accuracy: 0.0001)
        XCTAssertEqual(viewport.midY, bounds.midY, accuracy: 0.0001)
        let corner = SnapLayoutProjection.frame(for: .topRightQuarter, in: bounds, margins: .zero)
        XCTAssertEqual(corner.maxX, bounds.maxX, accuracy: 0.0001,
                       "A tile at the screen's right edge must touch the visible right edge")
        XCTAssertEqual(corner.minY, bounds.minY, accuracy: 0.0001,
                       "A tile at the screen's top edge must touch the visible top edge")
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
