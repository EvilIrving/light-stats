//
//  AppDelegate+WindowSnap.swift
//  Light Stats
//
//  Wires the drag-to-edge pipeline: the mouse monitor, the footprint preview, and the layout island.
//

import AppKit

extension AppDelegate {

    /// Wires the callbacks once, at launch. Everything after that is configuration-driven.
    func configureWindowSnapPipeline() {
        windowDragMonitorService.onUpdate = { [weak self] state in
            self?.handleWindowDragUpdate(state)
        }
        windowDragMonitorService.onDrop = { [weak self] state in
            self?.handleWindowDrop(state)
        }
        windowDragMonitorService.onCancel = { [weak self] in
            self?.tearDownDragOverlays()
        }
        windowDragMonitorService.onShake = { [weak self] window in
            self?.windowSnappingService.performShake(keeping: window.processID)
        }
    }

    /// Pushes the current configuration into every window-snap component and starts or stops the
    /// drag monitor to match.
    func syncWindowSnapPipeline() {
        applyWindowSnapConfiguration(settings.windowSnap)
    }

    func applyWindowSnapConfiguration(_ configuration: SnapConfiguration) {
        windowSnappingService.update(configuration: configuration)
        windowDragMonitorService.update(configuration: configuration)
        snapIslandController.update(configuration: configuration)
        if settings.windowManagementEnabled {
            windowSnapHotKeyService.start(shortcuts: configuration.shortcuts)
            // 拖到边缘只能是「一边负责」：把选择镜像到 macOS 自己的两个开关。
            SystemWindowTilingSetting.reconcile(owner: configuration.edgeOwner)
        } else {
            windowSnapHotKeyService.stop()
        }
        rebuildWindowControlsMenu()
        syncWindowPreviewPipeline(configuration)

        let shouldRunDragMonitor = settings.windowManagementEnabled && configuration.isDragSnappingActive
        if shouldRunDragMonitor {
            // A missing permission is not announced from here. The titles above already prompt when
            // the shortcuts cannot register, and a modal alert fired by an unrelated settings tweak
            // is worse than useless; the Settings page carries a persistent notice instead.
            _ = windowDragMonitorService.isRunning || windowDragMonitorService.start()
        } else {
            windowDragMonitorService.stop()
            tearDownDragOverlays()
            // Hidden applications stay hidden: bringing them back when the master switch is turned
            // off would be a side effect nobody asked for. Only the bookkeeping is dropped, so a
            // later "restore" cannot claim to have hidden them.
            windowSnappingService.forgetHiddenApplications()
        }

        // The Dock click is a click monitor, not a drag monitor: it runs whenever the feature is on,
        // including when every drag zone is switched off.
        dockClickService.update(configuration: configuration)
        let shouldRunDockClick = settings.windowManagementEnabled && configuration.isDockClickCollapseEnabled
        if shouldRunDockClick {
            _ = dockClickService.isRunning || dockClickService.start()
        } else {
            dockClickService.stop()
        }
    }

    // MARK: - Drag handling

    func handleWindowDragUpdate(_ state: WindowDragState) {
        let configuration = settings.windowSnap

        guard state.isMoving else {
            tearDownDragOverlays()
            return
        }

        // The island replaces the footprint: showing both at once would be two rectangles claiming
        // to be the answer.
        if state.zone.isIslandActive, !snapIslandController.isShowing {
            windowSnapPreview.hide()
            snapIslandController.present(on: state.zone.screen)
            snapIslandController.updatePointer(state.pointer)
            return
        }

        // While the island is on screen it owns the pointer: the tiles extend well below the top
        // edge, so the activation band cannot be what keeps it alive — the panel's own frame is.
        if snapIslandController.isShowing {
            snapIslandController.move(to: state.zone.screen)
            if snapIslandController.updatePointer(state.pointer) {
                showDragPreview(
                    target: snapIslandController.hoveredTarget,
                    state: state,
                    configuration: configuration
                )
                return
            }
            snapIslandController.dismiss()
        }

        showDragPreview(target: state.zone.target, state: state, configuration: configuration)
    }

    private func showDragPreview(target: SnapTarget?, state: WindowDragState, configuration: SnapConfiguration) {
        guard let target, configuration.showsPreview else {
            windowSnapPreview.hide()
            return
        }

        guard let frameAX = windowSnappingService.previewFrame(
            for: target,
            screen: state.zone.screen,
            currentSize: state.windowFrame?.size ?? .zero
        ) else {
            windowSnapPreview.hide()
            return
        }

        windowSnapPreview.show(
            frame: ScreenGeometryProvider.toCocoa(frameAX),
            cameFrom: state.windowFrame.map { ScreenGeometryProvider.toCocoa($0) }
        )
    }

    private func handleWindowDrop(_ state: WindowDragState) {
        defer { tearDownDragOverlays() }
        guard settings.windowManagementEnabled, let window = state.draggedWindow else { return }
        let islandTarget = snapIslandController.commitDrop(at: state.pointer)
        let target = SnapDropPolicy.target(
            islandOwnsDrop: snapIslandController.contains(state.pointer),
            islandTarget: islandTarget,
            edgeTarget: state.zone.target
        )
        guard let target else { return }
        windowSnappingService.perform(
            target, on: window.element, processID: window.processID, screen: state.zone.screen
        )
    }

    func tearDownDragOverlays() {
        if snapIslandController.isShowing {
            snapIslandController.dismiss()
        }
        if windowSnapPreview.isVisible {
            windowSnapPreview.hide()
        }
    }

    /// Suspends the drag pipeline while one of our own panels is in front.
    func setWindowSnapPipelineSuspended(_ suspended: Bool) {
        windowDragMonitorService.setSuspended(suspended)
        // A Dock click is not a drag, but the reason is the same: one of our own panels is in front,
        // and a click that lands on it must not put another app's windows away behind it.
        dockClickService.setSuspended(suspended)
    }
}
