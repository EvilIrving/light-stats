//
//  SnapIslandWindow.swift
//  Light Stats
//

import AppKit

/// The panel the layout island lives in.
///
/// One override matters more than everything else in this file: `constrainFrameRect(_:to:)`. AppKit
/// clamps every window to the screen's *visible* area, which puts the top of the panel below the
/// menu bar — the island would then hang 38pt down from the screen edge and the whole "grows out of
/// the top" idea would be gone. Returning the rect unchanged is what allows the panel to sit flush
/// against the physical top edge, where it covers the menu bar while a drag is in progress.
///
/// Wins' `SnappingIslandWindow` overrides exactly this one method, which is how it was identified
/// during the teardown.
final class SnapIslandWindow: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the menu bar (`.mainMenu` is 24), because the island is designed to overlap it.
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // The island never takes clicks. The drag that summoned it is still in progress and a panel
        // that accepted the mouse would end that drag; the drop is resolved by hit-testing the
        // pointer against the same tiles the view draws.
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
