//
//  HitRetainingHostingView.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// Keeps mouse / scroll events inside the popover when SwiftUI has no painted
/// descendant at a point. Real controls and scroll views keep normal hit targets.
/// Unhandled `scrollWheel` is absorbed so a non-opaque panel does not forward
/// wheel events through to the desktop (macOS 26). Does not paint or change colors.
///
/// Non-generic on purpose: a generic `NSHostingView<Content>` subclass trips a
/// Xcode 26.x SIL `EarlyPerfInliner` crash in Release/WMO on the synthesised
/// deinit (`HitRetainingHostingView.deinit`). Erasing through `AnyView` keeps
/// the hit/scroll contract without the compiler bug.
final class HitRetainingHostingView: NSHostingView<AnyView> {
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    convenience init(rootView: some View) {
        self.init(rootView: AnyView(rootView))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) ?? (bounds.contains(point) ? self : nil)
    }

    override func scrollWheel(with _: NSEvent) {
        // Descendants that handle scrolling receive the event via hit-testing.
        // Anything that lands here must not continue past this panel.
    }
}
