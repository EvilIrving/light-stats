//
//  AppSwitcherView.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// The ⌘Tab panel: the system switcher's row of application icons, plus a preview box under it.
///
/// The row is deliberately the system's: icons only, sized so the whole row fits the screen, never a
/// scroll view. The window preview under it is what the system does not have — it can land on a
/// *window*, not just an application.
///
/// Keyboard and pointer are two halves of one model: Tab and the arrows move the same selection the
/// pointer does, hovering selects what a click would take, and a click takes it without waiting for
/// ⌘ to come up. Nothing here holds a selection of its own — every change goes through the service.
struct AppSwitcherView: View {

    let session: AppSwitcherSession
    let metrics: AppSwitcherLayout.Metrics
    let thumbnailService: WindowThumbnailService?
    var onHover: (AppSwitcherPointerTarget) -> Void = { _ in }
    var onChoose: (AppSwitcherPointerTarget) -> Void = { _ in }

    /// Which rows the pointer put the selection on. A selection that came from the pointer needs no
    /// scrolling — the thing is already under the pointer — and scrolling it to the middle would put
    /// a *different* card under the pointer, which selects it, which scrolls again.
    @State private var hoveredGroupID: pid_t?
    @State private var hoveredWindowID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let row = metrics.appRow {
                appRow(row)
                Spacer().frame(height: AppSwitcherLayout.appRowSpacing)
            }
            windowStrip
        }
        .padding(AppSwitcherLayout.panelPadding)
        .modifier(AppSwitcherPanelMaterial(cornerRadius: Self.cornerRadius))
        .frame(width: metrics.panelSize.width, height: metrics.panelSize.height)
    }

    /// The panel's corners, and the radius every layer in it is clipped to.
    private static let cornerRadius: CGFloat = 26

    /// The application row: icons only, exactly as many per row as the layout worked out. There is no
    /// scroll view here on purpose — the system's row does not scroll either, it resizes.
    private func appRow(_ row: AppSwitcherLayout.AppRow) -> some View {
        let cell = AppSwitcherLayout.AppChip.cellSize(iconSize: row.iconSize)
        let columns = Array(
            repeating: GridItem(.fixed(cell), spacing: AppSwitcherLayout.AppChip.spacing),
            count: max(row.perRow, 1)
        )
        return LazyVGrid(columns: columns, spacing: AppSwitcherLayout.AppChip.spacing) {
            ForEach(Array(session.groups.enumerated()), id: \.element.id) { index, group in
                appChip(group: group, index: index, iconSize: row.iconSize)
            }
        }
        .frame(width: AppSwitcherLayout.contentWidth(for: metrics), alignment: .leading)
    }

    private func appChip(group: ApplicationWindowGroup, index: Int, iconSize: CGFloat) -> some View {
        let isSelected = index == session.groupIndex
        return appIcon(for: group)
            .frame(width: iconSize, height: iconSize)
            .padding(AppSwitcherLayout.AppChip.platePadding)
            .background(
                RoundedRectangle(cornerRadius: iconSize * 0.28, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.20) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: iconSize * 0.28, style: .continuous))
            .onHover { inside in
                guard inside else { return }
                hoveredGroupID = group.id
                onHover(.application(index))
            }
            .onTapGesture { onChoose(.application(index)) }
            // 名字只在这里：图标排本身不带文字，但悬停提示和 VoiceOver 必须能报出是谁。
            .help(group.displayName)
            .accessibilityLabel(group.displayName)
    }

    private var windowStrip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: AppSwitcherLayout.cardSpacing) {
                    if let group = session.selectedGroup {
                        ForEach(Array(group.windows.enumerated()), id: \.element.id) { index, item in
                            WindowPreviewCard(
                                item: item,
                                size: metrics.cardSize,
                                isSelected: index == session.windowIndex,
                                showsAppName: false,
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
                        }
                    }
                }
                // 预览框靠左，不居中：居中会让它两边各空一块，看着像没放满。它属于左边第一个图标
                // 下面那一格，靠左才看得出这个从属关系。
                .frame(minWidth: AppSwitcherLayout.contentWidth(for: metrics), alignment: .leading)
            }
            .scrollIndicators(.never)
            // 只有当窗口确实多到装不下时才滚：面板宽度已经按张数算过了，一两条窗口的时候滚一下
            // 除了闪出一条滚动条之外什么也没发生。
            .onChange(of: session.selectedWindow?.id, initial: true) { _, id in
                guard let id, id != hoveredWindowID, metrics.overflowCount > 0 else { return }
                reader.scrollTo(id, anchor: .center)
            }
        }
        .frame(height: metrics.cardSize.height)
    }

    @ViewBuilder
    private func appIcon(for group: ApplicationWindowGroup) -> some View {
        if let icon = NSRunningApplication(processIdentifier: group.processID)?.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

/// The panel's own material.
///
/// The switcher replaces a system control, so it gets the system's material: on macOS 26 that is
/// Liquid Glass, which is the only way to get that refraction — a material view plus a tint cannot
/// imitate it. Below 26 it falls back to the HUD material with a *light* tint: the panel used to sit
/// under `black.opacity(0.70)`, which covered the material completely and made the whole thing read as
/// a black box.
private struct AppSwitcherPanelMaterial: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.45), lineWidth: 0.5)
                )
        }
    }
}
