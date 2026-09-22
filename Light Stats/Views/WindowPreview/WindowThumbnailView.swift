//
//  WindowThumbnailView.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// A window's picture, or a legible stand-in for it.
///
/// The stand-in is not a failure state, it is the normal one: without Screen Recording permission
/// every card renders this way, and it still shows the window's icon and title — which is most of
/// what the preview is for. That is what lets the Dock preview and the switcher exist at all for a
/// user who has not granted the permission, instead of the features simply being absent.
///
/// It is drawn immediately and always, never as a loading state. A switcher session rebuilds every
/// card, so a spinner here means the panel opens as a row of spinners on every single ⌘Tab; the
/// application icon is available at once and the capture fades in over it when it arrives.
struct WindowThumbnailView: View {

    let windowID: CGWindowID?
    let size: CGSize
    let title: String
    let bundleIdentifier: String?
    /// `nil` when thumbnails are switched off, which is not the same as "not granted yet": with the
    /// feature off we do not even ask the service.
    let service: WindowThumbnailService?

    @State private var image: CGImage?
    /// A capture was attempted and produced nothing — permission missing, or the window is gone.
    @State private var captureFailed = false

    var body: some View {
        ZStack {
            standIn
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: requestKey) {
            await load()
        }
    }

    /// Re-runs the capture when either the window or the requested size changes, and not when the
    /// view merely re-renders — SwiftUI cancels and restarts a `task(id:)` on every change of `id`.
    private var requestKey: String {
        guard let windowID else { return "none" }
        return "\(windowID)-\(Int(size.width))-\(service != nil)"
    }

    private var standIn: some View {
        ZStack {
            Color.white.opacity(0.05)
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: glyphSize, height: glyphSize)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: glyphSize * 0.8, weight: .light))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        // 没图的时候至少说清楚为什么：缩略图开关关掉是自己的选择，就不标了。
        .overlay(alignment: .bottomTrailing) {
            if captureFailed {
                Image(systemName: "eye.slash")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(6)
                    .accessibilityLabel("settings.snap.screenRecording.needed".localized)
            }
        }
    }

    private var glyphSize: CGFloat {
        min(max(min(size.width, size.height) * 0.26, 18), 40)
    }

    private var appIcon: NSImage? {
        guard let bundleIdentifier else { return nil }
        if let cached = Self.iconCache.object(forKey: bundleIdentifier as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        Self.iconCache.setObject(icon, forKey: bundleIdentifier as NSString)
        return icon
    }

    /// 每个 bundle id 只问一次 LaunchServices：一次会话里每张卡片都要图标，每次都去查会把首帧拖住。
    private static let iconCache = NSCache<NSString, NSImage>()

    private func load() async {
        image = nil
        captureFailed = false
        guard let service, let windowID else {
            // 缩略图开关关着：站位图就是最终样子。
            return
        }
        let captured = await service.thumbnail(for: windowID, width: size.width, title: title)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            image = captured
            captureFailed = captured == nil
        }
    }
}
