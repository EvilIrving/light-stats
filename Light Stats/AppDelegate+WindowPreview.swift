//
//  AppDelegate+WindowPreview.swift
//  Light Stats
//
//  Wires the Screen-Recording-backed surfaces: thumbnails, the Dock hover preview, and ⌘Tab.
//

import AppKit

extension AppDelegate {

    /// Wires the callbacks once, at launch.
    func configureWindowPreviewPipeline() {
        windowPreviewIndex.onRefresh = { [weak self] groups in
            guard let self, self.settings.windowManagementEnabled,
                  self.settings.windowSnap.isWindowThumbnailsEnabled, ScreenRecordingPermission.isGranted else { return }
            let recent = ApplicationOrdering.mostRecentlyUsed(groups: groups, recency: ApplicationActivationTracker.shared.order)
            let firstWindows = recent.compactMap { $0.windows.first }
            let remaining = recent.flatMap { Array($0.windows.dropFirst()) }
            let items = Array((firstWindows + remaining).prefix(6))
            Task { await self.windowThumbnailService.prewarm(items, width: 320) }
        }
        // ── Dock hover preview ────────────────────────────────────────────────
        dockHoverMonitor.onHover = { [weak self] target in
            self?.presentDockPreview(for: target)
        }
        dockHoverMonitor.onExit = { [weak self] in
            self?.dockPreviewController.dismiss()
        }
        dockPreviewController.onFrameChanged = { [weak self] frame in
            // The monitor needs the panel's frame so that travelling from the Dock icon into the
            // panel does not count as leaving the Dock.
            self?.dockHoverMonitor.previewFrame = frame
            if frame == nil { self?.clearUnusedThumbnails() }
        }
        dockPreviewController.onSelect = { [weak self] item in
            guard let self else { return }
            self.lastExternalApplicationPID = item.processID
            self.dockPreviewController.dismiss()
            AXCommandQueue.shared.async { _ = WindowListService.reveal(item) }
        }

        // ── ⌘Tab ──────────────────────────────────────────────────────────────
        appSwitcherService.sessionProvider = {
            // Runs on the event-tap thread: no Accessibility, no main actor, no allocation beyond
            // the array it copies.
            let groups = WindowPreviewIndex.shared.currentGroups()
            let ordered = ApplicationOrdering.mostRecentlyUsed(
                groups: groups,
                recency: ApplicationActivationTracker.shared.order
            )
            return AppSwitcherSession(groups: ordered)
        }
        appSwitcherService.onSessionChanged = { [weak self] session in
            guard let self else { return }
            self.appSwitcherController.show(session: session, on: self.appSwitcherScreen())
        }
        appSwitcherService.onSessionEnded = { [weak self] window in
            guard let self else { return }
            self.appSwitcherController.dismiss()
            self.clearUnusedThumbnails()
            guard let window else { return }
            self.lastExternalApplicationPID = window.processID
            AXCommandQueue.shared.async { _ = WindowListService.reveal(window) }
        }
    }

    /// Starts or stops everything that depends on Screen Recording, and pushes the configuration in.
    func syncWindowPreviewPipeline(_ configuration: SnapConfiguration) {
        windowPreviewIndex.update(
            configuration: configuration,
            enabled: settings.windowManagementEnabled && (configuration.isDockPreviewEnabled || configuration.isCommandTabPlusEnabled)
        )
        dockPreviewController.update(
            configuration: configuration,
            thumbnailService: windowThumbnailService
        )
        appSwitcherController.update(
            thumbnailService: windowThumbnailService,
            configuration: configuration
        )

        let enabled = settings.windowManagementEnabled
        if !enabled || !configuration.isWindowThumbnailsEnabled {
            Task { await windowThumbnailService.clearCache() }
        }

        if enabled, configuration.isDockPreviewEnabled {
            if !dockHoverMonitor.isRunning {
                _ = dockHoverMonitor.start()
            }
        } else {
            dockHoverMonitor.stop()
            dockPreviewController.dismissImmediately()
        }

        if enabled, configuration.isCommandTabPlusEnabled {
            if !appSwitcherService.isRunning {
                _ = appSwitcherService.start()
            }
        } else {
            appSwitcherService.stop()
            appSwitcherController.dismissImmediately()
        }
    }

    /// Suspends both preview surfaces — used while one of our own sheets is open, where eating ⌘Tab
    /// or popping a Dock preview would be actively wrong.
    func setWindowPreviewPipelineSuspended(_ suspended: Bool) {
        dockHoverMonitor.setSuspended(suspended)
        appSwitcherService.setSuspended(suspended)
    }

    /// Tells the thumbnail cache that authorization changed, so it stops short-circuiting.
    func refreshWindowThumbnailAuthorization() {
        guard ScreenRecordingPermission.isGranted else { return }
        Task {
            await windowThumbnailService.notePermissionGranted()
        }
    }

    private func clearUnusedThumbnails() {
        guard !dockPreviewController.isPanelVisible, !appSwitcherController.isPanelVisible else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.2))
            guard let self, !self.dockPreviewController.isPanelVisible, !self.appSwitcherController.isPanelVisible else { return }
            await self.windowThumbnailService.purgeExpired()
        }
    }

    // MARK: - Private

    /// Builds and shows the preview for a hovered Dock icon.
    ///
    /// The window list comes from the shared index, which is already cached, so the panel appears
    /// without waiting for Accessibility — and the icon-to-panel hand-off stays inside the hover
    /// delay the monitor already enforced.
    private func presentDockPreview(for target: DockHoverTarget) {
        Task { [weak self] in
            guard let self else { return }
            guard let group = await self.windowPreviewIndex.loadGroup(for: target.processID),
                  self.settings.windowManagementEnabled,
                  self.settings.windowSnap.isDockPreviewEnabled,
                  self.dockHoverMonitor.isPreviewing(target.processID) else { return }
            self.dockPreviewController.present(
                group: group,
                anchor: target.itemFrame,
                orientation: DockHoverMonitorService.dockOrientation()
            )
        }
    }

    /// The display the switcher should appear on: the one the pointer is on, falling back to the
    /// display holding the frontmost window.
    private func appSwitcherScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
    }
}
