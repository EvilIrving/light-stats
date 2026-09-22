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

    /// The pointer's half of the interaction: hovering selects, clicking switches. Both go straight
    /// to the service, which owns the session — the panel never keeps a selection of its own.
    var onHover: ((AppSwitcherPointerTarget) -> Void)?
    var onChoose: ((AppSwitcherPointerTarget) -> Void)?
    /// Where the panel ended up, in screen coordinates, or `nil` when it is gone. The event tap uses
    /// it so a click on the panel reaches the panel and a click anywhere else does not reach at all.
    var onFrameChanged: ((CGRect?) -> Void)?

    init() {
        // The panel takes the mouse now: hovering picks a window and clicking switches to it — the
        // same thing the system switcher does. The session still ends when ⌘ comes up, and a click
        // commits through the same path, so the two cannot disagree: the loser of the race finds an
        // empty session and does nothing.
        window = PreviewOverlayWindow(contentRect: .zero, acceptsMouse: true)
        // Pinned to dark on purpose. The panel is a floating HUD whose content is drawn for a dark
        // backing (white labels, dark cards); letting it follow the system appearance would give a
        // light glass panel with white text on it in light mode.
        window.appearance = NSAppearance(named: .darkAqua)
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

        // Sized to the application being shown, not to the widest one in the list. Reserving room for
        // the widest app left a panel that was mostly empty whenever the selected app had fewer
        // windows — the empty rectangle read as a broken panel. The cost is that Tab can resize the
        // panel, which is what the short frame animation below is for.
        let metrics = AppSwitcherLayout.metrics(
            windowCount: group.windows.count,
            appCount: session.groups.count,
            available: screen.visibleFrame.size,
            showsAppRow: session.groups.count > 1
        )
        let frame = AppSwitcherLayout.panelFrame(size: metrics.panelSize, available: screen.visibleFrame)

        rebuildContent(session: session, metrics: metrics)

        let wasShowing = isShowing
        if !isShowing {
            generation += 1
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        isShowing = true
        if wasShowing, window.frame != frame {
            // Already on screen: the content changed size because another application is selected, so
            // move there instead of teleporting. Same rule as the Dock preview.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
        // Accessibility coordinates, because that is what a `CGEvent` carries.
        onFrameChanged?(ScreenGeometryProvider.toAccessibility(frame))
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
        onFrameChanged?(nil)
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
        onFrameChanged?(nil)
        window.alphaValue = 0
        window.orderOut(nil)
        window.contentView = nil
        hostingView = nil
    }

    private func rebuildContent(session: AppSwitcherSession, metrics: AppSwitcherLayout.Metrics) {
        let content = AppSwitcherView(
            session: session,
            metrics: metrics,
            thumbnailService: thumbnailService,
            onHover: { [weak self] target in self?.onHover?(target) },
            onChoose: { [weak self] target in self?.onChoose?(target) }
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
