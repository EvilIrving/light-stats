//
//  DockPreviewController.swift
//  Light Stats
//

import AppKit
import OSLog
import SwiftUI

/// Owns the Dock hover preview panel.
///
/// The monitor finds the hovered Dock icon; this decides what to draw and where, and — critically —
/// keeps the panel alive while the pointer travels from the icon into the panel so a card can be
/// clicked. That hand-off is reported back to the monitor through `previewFrame`, which is why it is
/// a property there rather than state here.
@MainActor
final class DockPreviewController {

    private let logger = AppLogger(category: "DockPreview")
    private let window: PreviewOverlayWindow
    private var hostingView: NSHostingView<DockPreviewView>?

    private var configuration: SnapConfiguration = .default
    private var group: ApplicationWindowGroup?
    private var thumbnailService: WindowThumbnailService?
    private var generation: UInt64 = 0
    private var isShowing = false

    /// Called when the panel's frame changes, so the monitor knows what counts as "still hovering".
    var onFrameChanged: ((CGRect?) -> Void)?
    /// Called when the user clicks a card.
    var onSelect: ((WindowPreviewItem) -> Void)?

    init() {
        window = PreviewOverlayWindow(contentRect: .zero, acceptsMouse: true)
    }

    var isPanelVisible: Bool { isShowing }

    func update(configuration: SnapConfiguration, thumbnailService: WindowThumbnailService?) {
        self.configuration = configuration
        self.thumbnailService = configuration.isWindowThumbnailsEnabled ? thumbnailService : nil
    }

    // MARK: - Presentation

    func present(group: ApplicationWindowGroup, anchor: CGRect, orientation: DockOrientation) {
        guard configuration.isDockPreviewEnabled else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) }) ?? NSScreen.main else {
            return
        }
        guard !group.windows.isEmpty else { return }

        generation += 1
        self.group = group

        let available = screen.visibleFrame
        let metrics = DockPreviewLayout.metrics(
            windowCount: group.windows.count,
            available: available.size
        )
        let band = DockGeometry.band(
            screen: screen.frame,
            visibleFrame: screen.visibleFrame,
            orientation: orientation,
            fallbackDockFrame: nil
        )
        let frame = DockGeometry.previewFrame(
            anchoredTo: anchor,
            band: band,
            panelSize: metrics.panelSize,
            available: available,
            orientation: orientation
        )

        rebuildContent(metrics: metrics, orientation: orientation)
        window.setFrame(frame, display: true)
        if !isShowing {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        isShowing = true
        onFrameChanged?(frame)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        DiagnosticLogService.record(
            category: "windowManagement",
            action: "dockPreviewShown",
            fields: ["app": group.bundleIdentifier ?? group.displayName, "windows": String(group.windows.count)]
        )
    }

    func dismiss() {
        guard isShowing else { return }
        generation += 1
        isShowing = false
        group = nil
        onFrameChanged?(nil)

        let token = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                window?.orderOut(nil)
                self.window.contentView = nil
                self.hostingView = nil
            }
        }
    }

    func dismissImmediately() {
        generation += 1
        isShowing = false
        group = nil
        onFrameChanged?(nil)
        window.alphaValue = 0
        window.orderOut(nil)
        window.contentView = nil
        hostingView = nil
    }

    // MARK: - Private

    private func rebuildContent(metrics: DockPreviewLayout.Metrics, orientation: DockOrientation) {
        guard let group else { return }
        let content = DockPreviewView(
            group: group,
            metrics: metrics,
            orientation: orientation,
            thumbnailService: thumbnailService,
            onSelect: { [weak self] item in
                self?.onSelect?(item)
            }
        )
        if let hostingView {
            hostingView.rootView = content
            return
        }
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = window.contentLayoutRect
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hosting
        hostingView = hosting
    }
}
