//
//  WindowPreviewMatchPolicy.swift
//  Light Stats
//

import CoreGraphics

nonisolated enum WindowPreviewMatchPolicy {
    struct Candidate {
        var windowID: CGWindowID?
        var title: String?
        var frame: CGRect?
    }

    static func index(windowID: CGWindowID, title: String?, frame: CGRect, candidates: [Candidate]) -> Int? {
        if let direct = candidates.firstIndex(where: { $0.windowID == windowID }) { return direct }
        let indirect = candidates.indices.filter { candidates[$0].windowID == nil }
        var titleMatches: [Int] = []
        if let title, !title.isEmpty {
            titleMatches = indirect.filter { candidates[$0].title == title }
        }
        if titleMatches.count == 1 { return titleMatches.first }
        // A candidate that names itself and names itself *differently* is a different window, and
        // geometry cannot tell the two apart: every tab of a natively tabbed window (Fork, Safari,
        // Terminal) reports the frame of the tab that is currently showing, so matching on the frame
        // alone brings the document the user is *not* asking for forward. Only candidates that
        // cannot name themselves stay eligible for a geometric match.
        let unnamed = indirect.filter { (candidates[$0].title ?? "").isEmpty }
        let pool = titleMatches.isEmpty ? unnamed : titleMatches
        let matches = pool.filter { index in
            candidates[index].frame.map { WindowSnapGeometry.framesApproximatelyEqual($0, frame, tolerance: 3) } ?? false
        }
        // Maximized windows can share a frame. An ambiguous match must never focus a different document.
        return matches.count == 1 ? matches.first : nil
    }

    /// The tab button that shows `windowTitle`, among the window tabs an application publishes.
    ///
    /// A native window tab is a window the WindowServer lists and Accessibility does not: only the
    /// tab that is showing is an `AXWindow`, so the hidden ones arrive with no element that can be
    /// raised. Their tab buttons live in the tab bar of the window that *is* visible, titled after
    /// the window they hold, and pressing one is the only way to switch to that tab.
    static func tabIndex(windowTitle: String, tabTitles: [String]) -> Int? {
        guard !windowTitle.isEmpty else { return nil }
        let matches = tabTitles.indices.filter { tabTitles[$0] == windowTitle }
        // Two tabs under one title cannot be told apart, and pressing the wrong one switches the
        // user to a different document.
        return matches.count == 1 ? matches.first : nil
    }
}
