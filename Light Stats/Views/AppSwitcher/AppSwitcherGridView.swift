//
//  AppSwitcherGridView.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// The grid mode's panel: every window, once, in recency order.
///
/// The two-level panel is the system's rail plus one application's windows; this one drops the rail
/// and shows the same windows as a single field. It reuses `WindowPreviewCard`, so selection, the
/// minimized badge and the thumbnail-or-title fallback behave identically in both modes — the modes
/// differ in what is on the panel, not in what a card means.
///
/// With more windows than the display can fold into rows the field is taller than the panel, so it
/// scrolls — and it scrolls to the selection, or the Tab key would move a highlight the user cannot
/// see. Same rule as the two-level strip: a selection the *pointer* made is already on screen, and
/// scrolling it to the middle would put a different tile under the pointer, which would select it.
struct AppSwitcherGridView: View {

    let session: AppSwitcherSession
    let metrics: AppSwitcherGridLayout.Metrics
    let thumbnailService: WindowThumbnailService?
    var onHover: (AppSwitcherPointerTarget) -> Void = { _ in }
    var onChoose: (AppSwitcherPointerTarget) -> Void = { _ in }

    /// The tile the pointer put the selection on — see the type's note.
    @State private var hoveredWindowID: String?

    private static let cornerRadius: CGFloat = 26

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, alignment: .center, spacing: AppSwitcherGridLayout.spacing) {
                    ForEach(Array(session.flatWindows.enumerated()), id: \.element.id) { index, item in
                        WindowPreviewCard(
                            item: item,
                            size: metrics.tileSize,
                            isSelected: index == session.flatIndex,
                            showsAppName: true,
                            thumbnailService: thumbnailService
                        )
                        .id(item.id)
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onHover { inside in
                            guard inside else { return }
                            hoveredWindowID = item.id
                            onHover(.window(index))
                        }
                        .onTapGesture { onChoose(.window(index)) }
                        .help(item.title)
                    }
                }
                .frame(width: metrics.contentWidth, alignment: .center)
                .padding(AppSwitcherGridLayout.padding)
            }
            .scrollIndicators(metrics.isScrollable ? .automatic : .never)
            // Only a grid taller than its panel has anything to scroll to; scrolling a grid that
            // already fits moves nothing and can only jog the panel.
            .onChange(of: session.selectedWindow?.id, initial: true) { _, id in
                guard metrics.isScrollable, let id, id != hoveredWindowID else { return }
                reader.scrollTo(id, anchor: .center)
            }
            .modifier(AppSwitcherPanelMaterial(cornerRadius: Self.cornerRadius))
            .frame(width: metrics.panelSize.width, height: metrics.panelSize.height)
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(metrics.tileSize.width), spacing: AppSwitcherGridLayout.spacing),
            count: max(metrics.columns, 1)
        )
    }
}
