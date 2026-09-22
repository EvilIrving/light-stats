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
    private var hostingView: NSHostingView<AnyView>?

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

    /// Shows `group`'s preview — appearing, or moving the panel that is already on screen.
    ///
    /// Moving along the Dock is a *transition*, not a second appearance: the panel keeps its place
    /// and its contents are replaced. A single panel holding a single Dock item at a time is what
    /// makes the preview read as following the pointer instead of
    /// blinking between icons.
    func present(group: ApplicationWindowGroup, anchor: CGRect, orientation: DockOrientation) {
        guard configuration.isDockPreviewEnabled else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) }) ?? NSScreen.main else {
            return
        }
        guard !group.windows.isEmpty else { return }

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

        let isAnotherApplication = isShowing && self.group?.processID != group.processID
        generation += 1
        self.group = group

        rebuildContent(metrics: metrics, orientation: orientation, animated: isAnotherApplication)

        if isShowing {
            move(to: frame, animated: window.frame != frame)
        } else {
            appear(at: frame, anchor: anchor)
            isShowing = true
        }
        onFrameChanged?(frame)

        DiagnosticLogService.record(
            category: "windowManagement",
            action: "dockPreviewShown",
            fields: ["app": group.bundleIdentifier ?? group.displayName, "windows": String(group.windows.count)]
        )
    }

    /// The first appearance: the panel grows out of its Dock icon, in the same 0.18 s the hover
    /// delay already waited for. A plain fade over the icon's own label is what made the preview
    /// look like it was pasted on top of the Dock instead of coming out of it.
    private func appear(at frame: CGRect, anchor: CGRect) {
        window.setFrame(DockGeometry.appearanceStartFrame(final: frame, anchor: anchor), display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.32, 1)
            window.animator().alphaValue = 1
            window.animator().setFrame(frame, display: true)
        }
    }

    /// Slides and resizes the panel that is already on screen. Adjacent icons move it a little; a
    /// different window count resizes it, and both are the same animation.
    private func move(to frame: CGRect, animated: Bool) {
        guard animated else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            window.animator().setFrame(frame, display: true)
        }
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

    private func rebuildContent(
        metrics: DockPreviewLayout.Metrics,
        orientation: DockOrientation,
        animated: Bool
    ) {
        guard let group else { return }
        // Identifying the content by application is what lets the swap cross-fade: SwiftUI treats a
        // changed identity as an insertion and a removal, and the default transition is a fade.
        let content = DockPreviewView(
            group: group,
            metrics: metrics,
            orientation: orientation,
            thumbnailService: thumbnailService,
            onSelect: { [weak self] item in
                self?.onSelect?(item)
            }
        )
        .id(group.processID)
        if let hostingView {
            guard animated else {
                hostingView.rootView = AnyView(content)
                return
            }
            withAnimation(.easeOut(duration: 0.16)) {
                hostingView.rootView = AnyView(content)
            }
            return
        }
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = window.contentLayoutRect
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hosting
        hostingView = hosting
    }
}
