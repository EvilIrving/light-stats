//
//  UpdateWindowGeometry.swift
//  Light Stats
//

import CoreGraphics

/// Frame arithmetic for the update window.
///
/// `NSWindow.maxSize` caps the *frame*, title bar included, and AppKit clamps a
/// window the moment a smaller maximum is assigned. Deriving the content height
/// from the cap — instead of sizing the content first and capping afterwards —
/// is what keeps the window at the size it was created with on a small display.
nonisolated enum UpdateWindowGeometry {

    static let contentWidth: CGFloat = 408
    static let preferredContentHeight: CGFloat = 500
    /// Below this the message is unreadable, so a very short screen is allowed to
    /// overflow the 85% margin rather than produce a sliver of a window.
    static let minimumContentHeight: CGFloat = 240
    static let maximumWidth: CGFloat = 480

    /// The content height whose frame (content plus title bar) still fits inside
    /// `visibleHeight * 0.85`. A screen tall enough for the preferred height is
    /// unchanged.
    static func contentHeight(visibleHeight: CGFloat, chromeHeight: CGFloat) -> CGFloat {
        let capped = max(minimumContentHeight, visibleHeight * 0.85 - chromeHeight)
        return min(preferredContentHeight, capped)
    }

    static func frameHeight(visibleHeight: CGFloat, chromeHeight: CGFloat) -> CGFloat {
        contentHeight(visibleHeight: visibleHeight, chromeHeight: chromeHeight) + chromeHeight
    }

    /// The maximum frame size handed to the window. It is never smaller than the
    /// frame the window is created with, so assigning it cannot resize the window.
    static func maximumFrameHeight(visibleHeight: CGFloat, chromeHeight: CGFloat) -> CGFloat {
        frameHeight(visibleHeight: visibleHeight, chromeHeight: chromeHeight).rounded(.up)
    }
}
