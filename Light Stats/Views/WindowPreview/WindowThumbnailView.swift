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
struct WindowThumbnailView: View {

    let windowID: CGWindowID?
    let size: CGSize
    let title: String
    let bundleIdentifier: String?
    /// `nil` when thumbnails are switched off, which is not the same as "not granted yet": with the
    /// feature off we do not even ask the service.
    let service: WindowThumbnailService?

    @State private var image: CGImage?
    @State private var finished = false

    var body: some View {
        ZStack {
            placeholder
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

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.04)
            if finished {
                Image(systemName: "eye.slash")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.45))
                    .accessibilityLabel("settings.snap.screenRecording.needed".localized)
            } else {
                ProgressView().controlSize(.small).tint(.white.opacity(0.6))
            }
        }
    }

    private func load() async {
        image = nil
        finished = false
        guard let service, let windowID else {
            finished = true
            return
        }
        let captured = await service.thumbnail(for: windowID, width: size.width, title: title)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            image = captured
            finished = true
        }
    }
}
