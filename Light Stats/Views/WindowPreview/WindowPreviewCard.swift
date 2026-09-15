//
//  WindowPreviewCard.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// One window in a preview strip.
///
/// The same card serves the Dock hover preview and the ⌘Tab switcher, because they show the same
/// thing and a second implementation would drift: selected state, the minimized badge, the
/// thumbnail-or-title fallback all behave identically in both.
struct WindowPreviewCard: View {

    let item: WindowPreviewItem
    let size: CGSize
    var isSelected: Bool = false
    var showsAppName: Bool = false
    let thumbnailService: WindowThumbnailService?

    private var thumbnailHeight: CGFloat { size.height - AppSwitcherLayout.cardTitleHeight }

    var body: some View {
        VStack(spacing: 0) {
            thumbnail
            caption
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.16 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.12),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isSelected ? 1.03 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: isSelected)
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            WindowThumbnailView(
                windowID: item.windowID,
                size: CGSize(width: size.width, height: thumbnailHeight),
                title: item.title,
                bundleIdentifier: item.bundleIdentifier,
                service: thumbnailService
            )
            if item.isMinimized {
                Label {
                    Text("window.preview.minimized".localized)
                        .font(.system(size: 9, weight: .medium))
                } icon: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .padding(6)
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.middle)
            if showsAppName {
                Text(item.appName)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: AppSwitcherLayout.cardTitleHeight)
    }
}
