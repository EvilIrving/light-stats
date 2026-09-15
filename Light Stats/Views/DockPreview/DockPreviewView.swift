//
//  DockPreviewView.swift
//  Light Stats
//

import SwiftUI

/// The panel that appears above a Dock icon: the application's name, then one card per window.
struct DockPreviewView: View {

    let group: ApplicationWindowGroup
    let metrics: DockPreviewLayout.Metrics
    let orientation: DockOrientation
    let thumbnailService: WindowThumbnailService?
    let onSelect: (WindowPreviewItem) -> Void

    @State private var hoveredID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            strip
        }
        .padding(DockPreviewLayout.panelPadding)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .frame(width: metrics.panelSize.width, height: metrics.panelSize.height)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(group.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)
            Text("window.preview.count".localized(group.windows.count))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
        }
        .frame(height: DockPreviewLayout.headerHeight)
    }

    private var strip: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: DockPreviewLayout.cardSpacing) {
                ForEach(group.windows) { item in card(for: item) }
            }
        }
        .scrollIndicators(.automatic)
        .frame(height: metrics.cardSize.height)
    }

    private func card(for item: WindowPreviewItem) -> some View {
        WindowPreviewCard(
            item: item,
            size: metrics.cardSize,
            isSelected: hoveredID == item.id,
            thumbnailService: thumbnailService
        )
        .onHover { hovered in
            hoveredID = hovered ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .onTapGesture { onSelect(item) }
        .help(item.title)
    }

}
