//
//  SystemWindowTilingSettings.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import Combine
import Foundation
import OSLog

/// Observable read-back of macOS' own window-tiling switches.
///
/// These live in `com.apple.WindowManager`, not in our defaults. The system stays the source of
/// truth: mirroring the value into `SettingsManager` would let the two drift apart the moment the
/// user flips the switch in System Settings.
///
/// The page no longer offers them as switches — who owns the gesture is a single choice now, written
/// by `SystemWindowTilingSetting`. This type only reports what the system currently says, so the
/// conflict notice can name a disagreement the user caused elsewhere.
@MainActor
final class SystemWindowTilingSettings: ObservableObject {

    @Published private(set) var edgeDragEnabled: Bool
    @Published private(set) var topEdgeDragEnabled: Bool

    init() {
        edgeDragEnabled = SystemWindowTilingSetting.isEdgeDragEnabled
        topEdgeDragEnabled = SystemWindowTilingSetting.isTopEdgeDragEnabled
    }

    /// Re-reads the system values, for the case where the user changed them elsewhere.
    func reload() {
        edgeDragEnabled = SystemWindowTilingSetting.isEdgeDragEnabled
        topEdgeDragEnabled = SystemWindowTilingSetting.isTopEdgeDragEnabled
    }

    /// Whether macOS is listening for the gesture while Light Stats owns it.
    ///
    /// Always false before macOS 15, where the system has no drag-to-edge tiling to conflict with:
    /// the preference domain does not exist there, and reading a missing flag would otherwise report
    /// the system's shipped default as if the user had chosen it.
    var conflictsWithLightStats: Bool {
        guard SystemWindowTilingSetting.isAvailable else { return false }
        return edgeDragEnabled || topEdgeDragEnabled
    }

    /// Whether the gesture is live at all while macOS owns it.
    ///
    /// The mirror image of the check above: the system's two switches are the *only* implementation
    /// in that mode, so turning one off in System Settings leaves the drag doing nothing. Reported
    /// rather than assumed, because "the gesture quietly stopped working" is the worst failure this
    /// feature has.
    var isSystemOwnershipIntact: Bool {
        guard SystemWindowTilingSetting.isAvailable else { return true }
        return edgeDragEnabled && topEdgeDragEnabled
    }

    /// Adopts the owner the user just picked.
    ///
    /// Called from the picker as well as from the AppDelegate's configuration sink. `reconcile`
    /// writes only on a transition, so whichever gets there first does the work and the other is a
    /// no-op — and calling it here is what makes the read-back below the system's real answer instead
    /// of a guess at whether the write landed.
    func adoptOwner(_ owner: SnapEdgeOwner) {
        SystemWindowTilingSetting.reconcile(owner: owner)
        reload()
    }

    /// Hands the gesture back to Light Stats and re-reads the result, so the notice disappears only
    /// once the system really reports the switch off.
    func giveGestureBackToLightStats() {
        SystemWindowTilingSetting.apply(.lightStats)
        reload()
    }

    /// Re-writes the system's own half of the handover after the user turned it off elsewhere.
    func reassertSystemOwnership() {
        SystemWindowTilingSetting.apply(.system)
        reload()
    }
}
