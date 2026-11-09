//
//  DragAppIconView.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// The app icon the user drags into the Privacy list.
///
/// A real `NSDraggingSource` rather than SwiftUI's `.onDrag`: the guide needs the drag session's
/// own settings (`animatesToStartingPositionsOnCancelOrFail`, no formation) and it needs the
/// payload to be exactly one file URL, which is what System Settings validates. SwiftUI's drag
/// providers put a promise on the pasteboard and add a text flavour — harmless everywhere else, and
/// a rejected drop here.
struct DragAppIconView: NSViewRepresentable {

    let url: URL

    func makeNSView(context: Context) -> DragAppIconNSView {
        DragAppIconNSView(bundleURL: url)
    }

    func updateNSView(_ nsView: DragAppIconNSView, context: Context) {
        nsView.bundleURL = url
    }
}

/// An icon you can pick up.
final class DragAppIconNSView: NSView, NSDraggingSource {

    /// A press becomes a drag after this much travel, so a click that misses the back button does
    /// not start a session that immediately cancels.
    private let dragThreshold: CGFloat = 3
    private var pressedAt: NSPoint?

    var bundleURL: URL {
        didSet {
            guard bundleURL != oldValue else { return }
            cachedIcon = nil
            needsDisplay = true
        }
    }

    private var cachedIcon: NSImage?

    init(bundleURL: URL) {
        self.bundleURL = bundleURL
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var icon: NSImage {
        if let cachedIcon { return cachedIcon }
        let image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        cachedIcon = image
        return image
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 52, height: 52)
    }

    /// The card is up while System Settings is frontmost, so this app is **inactive** and the panel
    /// can never be key. AppKit treats a mouse-down in that state as an activation click and drops
    /// it unless the view says otherwise — and `NSView` says `false`. Without this the press never
    /// arrives, `pressedAt` stays `nil`, and the one gesture the card exists for silently does
    /// nothing on every attempt.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        pressedAt = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        pressedAt = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressedAt else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= dragThreshold else { return }
        pressedAt = nil
        beginDrag(with: event)
    }

    /// One item, one file URL.
    ///
    /// System Settings reads the item as a Finder file drag; the item's dragging frame is the icon
    /// itself so the thing under the pointer is the thing that lands in the list.
    private func beginDrag(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: icon)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}
