//
//  AppSwitcherController.swift
//  Light Stats
//

import AppKit
import OSLog
import SwiftUI

/// Owns the ⌘Tab switcher panel.
///
/// Draws whatever session the service reports and nothing else: the selection model, the key
/// handling, and the commit all live in `AppSwitcherService` and `AppSwitcherSession`. This class is
/// the part that has to touch a window, which is exactly the part that cannot be unit tested, so it
/// is kept as thin as it can be.
@MainActor
final class AppSwitcherController {

    private let logger = AppLogger(category: "AppSwitcher")
    private let window: PreviewOverlayWindow
    private var hostingView: NSHostingView<AppSwitcherView>?
    private var thumbnailService: WindowThumbnailService?

    private var generation: UInt64 = 0
    private var isShowing = false

    init() {
        // The switcher is keyboard-driven: it ends when ⌘ is released, so a click arriving mid-session
        // would race the commit.
        window = PreviewOverlayWindow(contentRect: .zero, acceptsMouse: false)
    }

    var isPanelVisible: Bool { isShowing }

    func update(thumbnailService: WindowThumbnailService?, configuration: SnapConfiguration) {
        self.thumbnailService = configuration.isWindowThumbnailsEnabled ? thumbnailService : nil
    }

    /// Draws `session`. Called on every Tab, so it must be cheap after the first frame.
    func show(session: AppSwitcherSession, on screen: NSScreen?) {
        guard let group = session.selectedGroup else {
            dismiss()
            return
        }
        let screen = screen ?? NSScreen.main
        guard let screen else { return }

        // Reserve room for the widest application in the list, so the panel does not resize as the
        // user tabs through applications with different window counts.
        let largestWindowCount = session.groups.map(\.windows.count).max() ?? group.windows.count
        let available = screen.visibleFrame.insetBy(dx: 24, dy: 24).size
        let metrics = AppSwitcherLayout.metrics(
            windowCount: largestWindowCount,
            available: available,
            showsAppRow: session.groups.count > 1
        )
        let frame = AppSwitcherLayout.panelFrame(size: metrics.panelSize, available: screen.visibleFrame)

        rebuildContent(session: session, metrics: metrics, showsAppRow: session.groups.count > 1)

        if !isShowing {
            generation += 1
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        window.setFrame(frame, display: true)
        isShowing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isShowing else { return }
        generation += 1
        isShowing = false
        let token = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
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
        window.alphaValue = 0
        window.orderOut(nil)
        window.contentView = nil
        hostingView = nil
    }

    private func rebuildContent(session: AppSwitcherSession, metrics: AppSwitcherLayout.Metrics, showsAppRow: Bool) {
        let content = AppSwitcherView(
            session: session,
            metrics: metrics,
            showsAppRow: showsAppRow,
            thumbnailService: thumbnailService
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
