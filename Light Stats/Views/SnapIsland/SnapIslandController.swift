//
//  SnapIslandController.swift
//  Light Stats
//

import AppKit
import OSLog
import SwiftUI

/// Owns the layout island: the panel, its animation, and the drop hit-testing.
///
/// Two ideas are kept apart on purpose, because collapsing them is what makes an island blink:
///
/// - `SnapIslandState` is the resting geometry — `collapsed` or `open`.
/// - `SnapMotion` is how it got there — `show`, `expand`, `collapse`, `hide`, `resize`.
///
/// A screen change or a layout change is a `resize`: the same state with new geometry. Replaying
/// `show` for it is the classic island flicker.
///
/// Geometry is always taken from the **settled** frame for the current state, never from the
/// panel's animating frame. The view draws against the same settled size and is clipped by the
/// panel as it grows, so what the user aims at never moves under the animation, and hit-testing and
/// drawing cannot disagree.
@MainActor
final class SnapIslandController {

    private let logger = AppLogger(category: "SnapIsland")
    private let panel: SnapIslandWindow
    private let model = SnapIslandViewModel()
    private var hostingView: NSHostingView<SnapIslandView>?
    private var driver = SnapAnimationDriver()

    private var configuration: SnapConfiguration = .default
    private var screen: SnapScreenGeometry?
    private var state: SnapIslandState = .collapsed
    private var isVisible = false
    /// Incremented on every dismissal, so an in-flight hide animation cannot be resumed by a show
    /// that raced it. Wins keeps the same token (`hideAnimationGeneration`).
    private var generation: UInt64 = 0

    init() {
        panel = SnapIslandWindow(contentRect: .zero)
    }

    var isShowing: Bool { isVisible }
    var currentState: SnapIslandState { state }
    var hoveredTarget: SnapTarget? {
        guard let segment = model.activeLayout?.segments.first(where: { $0.id == model.hoveredSegmentID }) else { return nil }
        return .region(segment.rect)
    }

    func contains(_ point: CGPoint) -> Bool {
        guard isVisible, let screen else { return false }
        return settledAXRect(for: .open, on: screen).contains(point)
    }

    func move(to screen: SnapScreenGeometry) {
        guard screen.frame.width > 0, self.screen != screen else { return }
        self.screen = screen
        model.screenSize = screen.visibleFrame.size
        applyGeometryChange()
    }

    /// The configuration the island renders with. Layered on top of the next pointer update.
    func update(configuration: SnapConfiguration) {
        self.configuration = configuration
        model.layouts = configuration.islandLayouts
        if !model.layouts.contains(where: { $0.id == model.activeLayoutID }) {
            model.activeLayoutID = model.layouts.first?.id
        }
        rebuildContent()
        if isVisible {
            if model.layouts.isEmpty { dismissImmediately() } else { applyGeometryChange() }
        }
    }

    // MARK: - Presentation

    /// Shows the collapsed strip on `screen`.
    ///
    /// It deliberately does not expand here: expansion follows the pointer entering the strip, so a
    /// drag that merely passes over the top edge does not throw a full panel onto the screen.
    func present(on screen: SnapScreenGeometry) {
        guard configuration.zones.topEdgeMode == .island else { return }
        let layouts = configuration.islandLayouts
        guard !layouts.isEmpty else {
            logger.debug("Island requested with no layouts configured")
            return
        }

        generation += 1
        self.screen = screen
        model.screenSize = screen.visibleFrame.size
        model.layouts = layouts
        model.activeLayoutID = layouts.first?.id
        model.reset()

        state = .collapsed
        model.isExpanded = false
        model.openProgress = 0
        model.contentSize = settledSize(for: .open, on: screen)
        model.collapsedSize = settledSize(for: .collapsed, on: screen)

        rebuildContent()
        panel.setFrame(settledCocoaRect(for: .open, on: screen), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        isVisible = true

        // A single plan carries the fade *and* the growth. Two plans would mean the second cancels
        // the first, and the island would spend its whole life at the alpha the first one left it.
        let plan = SnapAnimationPlan(
            startFrame: panel.frame,
            targetFrame: panel.frame,
            startAlpha: 0,
            targetAlpha: 1,
            motion: .show,
            timing: .islandExpand,
            animatesGeometry: false
        )
        driver.run(plan: plan) { [weak self] sample in
            self?.panel.alphaValue = CGFloat(sample.alpha)
        }

        DiagnosticLogService.record(category: "windowManagement", action: "islandPresented")
    }

    /// Re-lays the island out without replaying an appearance — a screen change, or a layout the
    /// user edited while the island was on screen. This is the `resize` path.
    func applyGeometryChange() {
        guard isVisible, let screen else { return }
        transition(to: state, on: screen)
        DiagnosticLogService.record(
            category: "windowManagement",
            action: "islandResized",
            fields: ["state": state.rawValue]
        )
    }

    func dismiss(animated: Bool = true) {
        guard isVisible else { return }
        generation += 1
        let startProgress = model.openProgress
        let wasOpen = state == .open
        isVisible = false
        state = .collapsed
        model.isExpanded = false
        model.reset()

        if !animated {
            driver.cancel()
            panel.alphaValue = 0
            panel.orderOut(nil)
            model.openProgress = 0
            return
        }

        let plan = SnapAnimationPlan(
            startFrame: panel.frame,
            targetFrame: panel.frame,
            startAlpha: Double(panel.alphaValue),
            targetAlpha: 0,
            motion: wasOpen ? .collapse : .hide,
            timing: .islandCollapse,
            animatesGeometry: false
        )
        let token = generation
        driver.run(plan: plan) { [weak self] sample in
            self?.panel.alphaValue = CGFloat(sample.alpha)
            self?.model.openProgress = startProgress * (1 - min(max(sample.progress, 0), 1))
        } onFinish: { [weak self] in
            guard let self, self.generation == token else { return }
            self.panel.orderOut(nil)
            self.model.openProgress = 0
        }
    }

    /// Tears the panel down without animating — used when window management is switched off, where
    /// leaving a fading overlay behind would look like the switch did not work.
    func dismissImmediately() {
        generation += 1
        driver.cancel()
        panel.alphaValue = 0
        panel.orderOut(nil)
        isVisible = false
        state = .collapsed
        model.isExpanded = false
        model.reset()
        model.openProgress = 0
    }

    // MARK: - Pointer interaction

    /// Feeds the current pointer position, in Accessibility space.
    ///
    /// - Returns: whether the pointer is inside the island. `false` means the caller should dismiss
    ///   it, which is how a drag that leaves the panel — and the top edge with it — closes it.
    ///
    /// The check is against the **expanded** frame, not the activation band. Using the band would
    /// make the tiles unreachable: they extend well below the 12pt of the top edge that arms the
    /// island, so the island would vanish the moment the user lowered the pointer to aim.
    @discardableResult
    func updatePointer(_ point: CGPoint) -> Bool {
        guard isVisible, let screen else { return false }
        let panelFrame = settledAXRect(for: .open, on: screen)

        guard panelFrame.contains(point) else {
            model.reset()
            return false
        }

        if state == .collapsed {
            expand()
        }

        let local = CGPoint(x: point.x - panelFrame.minX, y: point.y - panelFrame.minY)
        let bounds = CGRect(origin: .zero, size: model.contentSize)

        let hit = SnapIslandLayout.hit(
            at: local, layouts: model.layouts, panel: bounds,
            margins: configuration.margins, sourceSize: model.screenSize
        )
        model.activeLayoutID = hit?.layoutID
        model.hoveredSegmentID = hit?.segment.id
        return true
    }

    /// The target the user released on, or `nil` when the release missed every tile.
    func commitDrop(at point: CGPoint) -> SnapTarget? {
        defer { model.reset() }
        guard isVisible, state == .open, let screen else { return nil }

        let panelFrame = settledAXRect(for: .open, on: screen)
        let local = CGPoint(x: point.x - panelFrame.minX, y: point.y - panelFrame.minY)
        guard let hit = SnapIslandLayout.hit(
            at: local, layouts: model.layouts, panel: CGRect(origin: .zero, size: model.contentSize),
            margins: configuration.margins, sourceSize: model.screenSize
        ) else { return nil }
        DiagnosticLogService.record(
            category: "windowManagement", action: "islandDrop",
            fields: ["layout": hit.layoutID, "segment": hit.segment.id]
        )
        return .region(hit.segment.rect)
    }

    // MARK: - Private

    private func expand() {
        guard isVisible, state != .open, let screen else { return }
        transition(to: .open, on: screen)
    }

    private func transition(to next: SnapIslandState, on screen: SnapScreenGeometry) {
        let motion = state.motion(to: next)
        let target = settledCocoaRect(for: .open, on: screen)
        panel.setFrame(target, display: true)
        let start = target
        let startProgress = model.openProgress
        let targetProgress = next == .open ? 1.0 : 0.0
        state = next
        model.isExpanded = next == .open
        // The view is told the destination size up front, so the tiles are never laid out against a
        // frame that is halfway through an animation.
        model.contentSize = settledSize(for: .open, on: screen)
        model.collapsedSize = settledSize(for: .collapsed, on: screen)

        let plan = SnapAnimationPlan(
            startFrame: start,
            targetFrame: target,
            startAlpha: Double(panel.alphaValue),
            targetAlpha: 1,
            motion: motion,
            timing: motion == .collapse ? .islandCollapse : .islandExpand,
            animatesGeometry: false
        )

        driver.run(plan: plan) { [weak self] sample in
            guard let self else { return }
            self.panel.alphaValue = CGFloat(min(max(sample.alpha, 0), 1))
            // Corner radii and the shadow ride the same 0→1 value as the geometry, which is what
            // makes the panel look like one object rather than a rectangle that changes size.
            self.model.openProgress = startProgress + (targetProgress - startProgress) * sample.progress
        }
    }

    private func settledAXRect(for state: SnapIslandState, on screen: SnapScreenGeometry) -> CGRect {
        var geometry = configuration.island
        let width = geometry.width(for: screen.frame)
        geometry.expandedHeight = SnapIslandLayout.preferredHeight(
            layoutCount: model.layouts.count, width: width, sourceSize: model.screenSize
        )
        return SnapIslandPolicy.frame(for: state, in: screen.frame, configuration: geometry)
    }

    private func settledCocoaRect(for state: SnapIslandState, on screen: SnapScreenGeometry) -> CGRect {
        ScreenGeometryProvider.toCocoa(settledAXRect(for: state, on: screen))
    }

    private func settledSize(for state: SnapIslandState, on screen: SnapScreenGeometry) -> CGSize {
        settledCocoaRect(for: state, on: screen).size
    }

    private func rebuildContent() {
        let content = SnapIslandView(
            model: model,
            margins: configuration.margins,
            palette: configuration.islandPalette
        )
        if let hostingView {
            hostingView.rootView = content
            return
        }
        let hosting = NSHostingView(rootView: content)
        // The panel's own frame animation is the only thing that decides the island's size. Without
        // this the hosting view resizes itself to its content, which fights the animation and makes
        // the panel jump to its final size on the first frame.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = panel.contentLayoutRect
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        hostingView = hosting
    }
}
