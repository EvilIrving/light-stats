//
//  DockPreviewWindow.swift
//  Light Stats
//

import AppKit

/// A shared click-through-free overlay panel for the preview surfaces.
///
/// Both the Dock hover preview and the ⌘Tab switcher are the same kind of object: a borderless panel
/// that floats above everything, joins every Space, survives full-screen applications, never becomes
/// key (taking focus away from the application the user is switching *from* would be a bug), and is
/// torn down the instant its feature is switched off.
///
/// One difference matters and is a parameter: the Dock preview must accept clicks so a card can be
/// chosen, while the switcher must not, because its session ends when ⌘ is released and a click
/// arriving mid-session would fight with that.
final class PreviewOverlayWindow: NSPanel {

    init(contentRect: NSRect, acceptsMouse: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the Dock and the menu bar: a Dock preview that appears *behind* the Dock is useless.
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = !acceptsMouse
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Preview panels hang below the Dock and beside the screen edge, so AppKit's clamp to the
    /// visible area — which excludes the Dock and the menu bar — would push them to the wrong place.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
