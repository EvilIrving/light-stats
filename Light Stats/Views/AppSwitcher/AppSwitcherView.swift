//
//  AppSwitcherView.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// The ⌘Tab panel: one chip per application, then the selected application's windows.
///
/// The window strip is what makes this different from the system switcher — it can land on a
/// *window*, not just an application, which is the reason Wins' version exists at all.
struct AppSwitcherView: View {

    let session: AppSwitcherSession
    let metrics: AppSwitcherLayout.Metrics
    let showsAppRow: Bool
    let thumbnailService: WindowThumbnailService?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsAppRow {
                appRow
                Spacer().frame(height: AppSwitcherLayout.appRowSpacing)
            }
            windowStrip
        }
        .padding(AppSwitcherLayout.panelPadding)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.70))
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .frame(width: metrics.panelSize.width, height: metrics.panelSize.height)
    }

    private var appRow: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(session.groups.enumerated()), id: \.element.id) { index, group in
                        appChip(group: group, isSelected: index == session.groupIndex).id(group.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: session.selectedGroup?.id, initial: true) { _, id in
                if let id { reader.scrollTo(id, anchor: .center) }
            }
        }
        .frame(height: AppSwitcherLayout.appRowHeight)
    }

    private func appChip(group: ApplicationWindowGroup, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            appIcon(for: group)
                .frame(width: 20, height: 20)
            Text(group.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.62))
                .lineLimit(1)
            if group.windows.count > 1 {
                Text("\(group.windows.count)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: AppSwitcherLayout.appRowHeight - 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.34) : Color.white.opacity(0.06))
        )
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
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: session.selectedWindow?.id, initial: true) { _, id in
                if let id { reader.scrollTo(id, anchor: .center) }
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
