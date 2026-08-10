//
//  ToastCenter.swift
//  Light Stats
//
//  轻量 toast:菜单栏下方居中浮现的一行提示,自动淡入淡出,不夺取焦点、不拦鼠标。
//  用于「已是最新版本」「检查失败」这类无需窗口的瞬时反馈。任何地方都可复用:
//  `ToastCenter.shared.show(...)`。
//

import AppKit
import SwiftUI

@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(message: String, systemImage: String, tint: Color, duration: TimeInterval = 2.0) {
        dismissTask?.cancel()

        let hosting = NSHostingView(rootView: ToastView(message: message, systemImage: systemImage, tint: tint))
        hosting.layout()
        let size = hosting.fittingSize

        let win = panel ?? makePanel()
        win.contentView = hosting
        win.setContentSize(size)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            win.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12))
        }

        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            win.animator().alphaValue = 1
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let win = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            win.animator().alphaValue = 0
        }, completionHandler: { [weak win] in
            win?.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let win = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.ignoresMouseEvents = true
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel = win
        return win
    }
}

// MARK: - Toast 内容

private struct ToastView: View {
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(12)
        .fixedSize()
    }
}
