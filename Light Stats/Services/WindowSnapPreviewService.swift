//
//  WindowSnapPreviewService.swift
//  Light Stats
//
//  Lightweight visual preview for titlebar window-snapping gestures.
//

import AppKit

@MainActor
final class WindowSnapPreviewService {
    private var overlayWindow: NSWindow?

    func show(frame: CGRect) {
        let window = overlayWindow ?? makeOverlayWindow()
        overlayWindow = window
        window.setFrame(frame, display: true)
        if !window.isVisible {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let window = overlayWindow else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
        }
    }

    private func makeOverlayWindow() -> NSWindow {
        let view = SnapPreviewView(frame: .zero)
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = view
        return window
    }
}

private final class SnapPreviewView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.72).cgColor
        layer?.borderWidth = 2
        layer?.cornerRadius = 14
    }
}
