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
        let titleMatches = indirect.filter { index in
            guard let title, !title.isEmpty else { return false }
            return candidates[index].title == title
        }
        if titleMatches.count == 1 { return titleMatches.first }
        let pool = titleMatches.isEmpty ? indirect : titleMatches
        let matches = pool.filter { index in
            candidates[index].frame.map { WindowSnapGeometry.framesApproximatelyEqual($0, frame, tolerance: 3) } ?? false
        }
        // Maximized windows can share a frame. An ambiguous match must never focus a different document.
        return matches.count == 1 ? matches.first : nil
    }
}
