//
//  SnapIslandView.swift
//  Light Stats
//

import SwiftUI

struct SnapIslandView: View {
    @Bindable var model: SnapIslandViewModel
    let margins: SnapMargins
    let palette: SnapIslandMetrics.Palette

    var body: some View {
        let bounds = CGRect(origin: .zero, size: model.contentSize)
        let progress = min(max(model.openProgress, 0), 1)
        let collapsedWidth = min(model.collapsedSize.width, bounds.width)
        let collapsedHeight = min(model.collapsedSize.height, bounds.height)
        let width = collapsedWidth + (bounds.width - collapsedWidth) * progress
        let height = collapsedHeight + (bounds.height - collapsedHeight) * progress
        ZStack(alignment: .topLeading) {
            shape.fill(Color(white: palette == .vivid ? 0.12 : 0.18).opacity(0.98))
                .overlay(shape.fill(accent.opacity(palette == .accent ? 0.12 : 0)))
            if model.isExpanded || progress > 0 {
                ForEach(SnapIslandLayout.tiles(
                    layouts: model.layouts, panel: bounds, margins: margins, sourceSize: model.screenSize
                ), id: \.id) { tile in
                    let selected = model.activeLayoutID == tile.layoutID && model.hoveredSegmentID == tile.segment.id
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? accent.opacity(0.60) : Color.white.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(.white.opacity(selected ? 0.85 : 0.28), lineWidth: selected ? 1 : 0.75)
                        }
                        .frame(width: tile.frame.width, height: tile.frame.height)
                        .offset(x: tile.frame.minX, y: tile.frame.minY)
                }
            } else {
                Capsule().fill(.white.opacity(0.35)).frame(width: 32, height: 3)
                    .position(x: bounds.midX, y: height - 8)
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .mask(alignment: .top) { shape.frame(width: width, height: height) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusable(false)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: SnapIslandMetrics.bottomCornerRadius,
            bottomTrailingRadius: SnapIslandMetrics.bottomCornerRadius, topTrailingRadius: 0
        )
    }

    private var accent: Color { palette == .vivid ? .white : .accentColor }
}
