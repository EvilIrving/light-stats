//
//  SnapInteractionPreview.swift
//  Light Stats
//

import SwiftUI

/// An interactive desktop using the same island view, hit tests and placement projection as the live gesture.
struct SnapInteractionPreview: View {
    @ObservedObject var settings: SettingsManager
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SnapIslandViewModel()
    @State private var isDragging = false
    @State private var showsIsland = false
    @State private var windowRect = SnapNormalizedRect(x: 0.32, y: 0.40, width: 0.36, height: 0.42)
    @State private var dragOrigin: SnapNormalizedRect?
    @State private var target: SnapTarget?
    @State private var previousZone: SnapZoneResult?

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let island = islandFrame(in: bounds)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(theme.wellFill)
                Rectangle().fill(theme.inkSecondary.opacity(0.08)).frame(height: 12)
                if let target, settings.windowSnap.showsPreview,
                   let rect = targetRect(target) {
                    windowShape(frame: SnapLayoutProjection.frame(
                        for: rect, in: bounds, margins: .zero
                    ), isPreview: true)
                        .allowsHitTesting(false)
                }
                windowShape(frame: projected(windowRect, in: bounds), isPreview: false)
                    .gesture(windowDrag(in: bounds))
                    .accessibilityLabel("settings.snap.editor.demoWindow".localized)
                if showsIsland {
                    SnapIslandView(model: model, palette: settings.windowSnap.islandPalette)
                        .frame(width: island.width, height: island.height, alignment: .topLeading)
                        .clipped()
                        .offset(x: island.minX, y: island.minY)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Button {
                    withAnimation(motion) {
                        windowRect = SnapNormalizedRect(x: 0.32, y: 0.40, width: 0.36, height: 0.42)
                        target = nil
                        showsIsland = false
                    }
                } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 11)) }
                    .buttonStyle(.borderless)
                    .padding(10)
                    .frame(width: bounds.width, height: bounds.height, alignment: .bottomTrailing)
                    .accessibilityLabel("settings.snap.editor.resetDemo".localized)
            }
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            .coordinateSpace(name: "snap-demo")
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        // The well is the screen, so it carries the reference display's shape rather than the
        // settings pane's width. `projected` centres the reference screen inside these bounds, and
        // the two must agree: a box stretched to the pane leaves the demo window short of the edges
        // it is supposed to be able to reach.
        .aspectRatio(SnapLayoutProjection.referenceAspect, contentMode: .fit)
        // 顶部对齐，不要居中：上限框比投影高出来的那几磅会变成一条无人认领的缝，练习场就再也
        // 对不上左边设置行的上边缘了。
        .frame(maxHeight: 260, alignment: .top)
        .onAppear(perform: sync)
        .onChange(of: settings.windowSnap) { _, _ in sync() }
    }

    private var motion: Animation { .easeOut(duration: reduceMotion ? 0.08 : 0.22) }

    private func projected(_ rect: SnapNormalizedRect, in bounds: CGRect) -> CGRect {
        // The demo window is projected through the same reference screen and gap rule as the
        // thumbnails; the well around it is the projection's viewport, so the two never disagree.
        SnapLayoutProjection.frame(for: rect, in: bounds, margins: .zero)
    }

    private func windowShape(frame: CGRect, isPreview: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(isPreview ? theme.accent.opacity(0.16) : theme.inkSecondary.opacity(0.14))
            .overlay(alignment: .topLeading) {
                if !isPreview {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { _ in Circle().fill(theme.inkSecondary.opacity(0.45)).frame(width: 4, height: 4) }
                        Spacer()
                        Image(systemName: "hand.draw").font(.system(size: 10)).foregroundStyle(theme.inkSecondary)
                    }
                    .padding(7)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.accent.opacity(isPreview ? 0.8 : 0.35), lineWidth: 1))
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }

    private func islandFrame(in bounds: CGRect) -> CGRect {
        let width = max(bounds.width - 24, 0)
        let height = SnapIslandLayout.preferredHeight(
            layoutCount: model.layouts.count, width: width, sourceSize: model.screenSize
        )
        return CGRect(x: 12, y: 0, width: width, height: min(height, bounds.height - 20))
    }

    private func windowDrag(in bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("snap-demo"))
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = windowRect
                    isDragging = true
                    previousZone = nil
                }
                guard let origin = dragOrigin else { return }
                let viewport = SnapLayoutProjection.viewport(in: bounds, sourceSize: SnapLayoutProjection.referenceSize)
                windowRect = SnapNormalizedRect(
                    x: origin.x + Double(value.translation.width / viewport.width),
                    y: origin.y + Double(value.translation.height / viewport.height),
                    width: origin.width, height: origin.height
                )
                updatePointer(value.location, in: bounds)
            }
            .onEnded { value in
                updatePointer(value.location, in: bounds)
                withAnimation(motion) {
                    if let target, let rect = targetRect(target) {
                        windowRect = rect
                    } else {
                        windowRect.x = min(max(windowRect.x, 0), 1 - windowRect.width)
                        windowRect.y = min(max(windowRect.y, 0), 1 - windowRect.height)
                    }
                    dragOrigin = nil
                    previousZone = nil
                    isDragging = false
                    showsIsland = false
                    target = nil
                    model.reset()
                }
            }
    }

    private func updatePointer(_ point: CGPoint, in bounds: CGRect) {
        let screen = SnapScreenGeometry(frame: bounds, visibleFrame: bounds)
        let zone = SnapZonePolicy.result(
            pointer: point, screen: screen, configuration: settings.windowSnap.effectiveZones, previous: previousZone
        )
        previousZone = zone
        let island = islandFrame(in: bounds)
        if zone.isIslandActive { withAnimation(motion) { showsIsland = true } }
        guard showsIsland else { target = zone.target; return }
        guard island.contains(point) else {
            withAnimation(motion) { showsIsland = false }
            target = zone.target
            return
        }
        model.contentSize = island.size
        withAnimation(motion) { model.isExpanded = true; model.openProgress = 1 }
        let local = CGPoint(x: point.x - island.minX, y: point.y - island.minY)
        let panel = CGRect(origin: .zero, size: island.size)
        let hit = SnapIslandLayout.hit(
            at: local, layouts: model.layouts, panel: panel, margins: .zero
        )
        model.activeLayoutID = hit?.layoutID
        model.hoveredSegmentID = hit?.segment.id
        target = hit.map { .region($0.segment.rect) }
    }

    private func targetRect(_ target: SnapTarget) -> SnapNormalizedRect? {
        guard case .region(let rect) = target else { return nil }
        return rect
    }

    private func sync() {
        model.layouts = settings.windowSnap.islandLayouts
        if !model.layouts.contains(where: { $0.id == model.activeLayoutID }) { model.activeLayoutID = model.layouts.first?.id }
        model.screenSize = SnapLayoutProjection.referenceSize
        if model.layouts.isEmpty { showsIsland = false }
    }
}
