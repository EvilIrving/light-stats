//
//  SnapMargins.swift
//  Light Stats
//

import CoreGraphics

/// Gaps applied to snapped windows.
///
/// Wins exposes four independent sliders (`marginTop/Bottom/Left/Right`) plus a separate enable
/// switch. Two values cover the same ground without needing a mode:
///
/// - `outer` — distance between a snapped window and the screen's visible edge.
/// - `inner` — distance between two adjacent snapped windows.
///
/// Zero is the classic edge-to-edge tiling, which is why a single `SnapMargins.zero` is a valid
/// "feature off" state and no enable flag is stored.
struct SnapMargins: Codable, Hashable, Sendable {

    /// The largest gap the UI can produce. Placement clamps to this so a hand-edited plist cannot
    /// push every window off screen.
    static let maximumGap: CGFloat = 64

    var outer: CGFloat
    var inner: CGFloat

    static let zero = SnapMargins(outer: 0, inner: 0)

    init(outer: CGFloat, inner: CGFloat) {
        self.outer = SnapMargins.clamp(outer)
        self.inner = SnapMargins.clamp(inner)
    }

    var isZero: Bool { outer == 0 && inner == 0 }

    /// Half of the inner gap, which each side of a shared edge contributes.
    var halfInner: CGFloat { inner / 2 }

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), maximumGap)
    }
}
