//
//  SystemWindowTilingSetting.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import Foundation
import OSLog

/// macOS' own drag-to-edge tiling, read and written through the domain macOS keeps it in.
///
/// Light Stats implements the same gesture itself, because the system's version has no custom
/// layouts and no island. Two implementations of one gesture cannot both be live: the system would
/// tile the window at the same moment the engine places it, and the result would depend on which
/// finished last. So the gesture is owned by exactly one side, and this type is where the system's
/// half of that handover is written.
///
/// The two switches are written together, never separately: macOS tiles the top edge as well as the
/// sides, so owning one of them and not the other would leave the same conflict at the menu bar.
enum SystemWindowTilingSetting {

    private static let domain = "com.apple.WindowManager"
    private static let edgeDragKey = "EnableTilingByEdgeDrag"
    private static let topEdgeDragKey = "EnableTopTilingByEdgeDrag"
    /// Which owner was last written to the system. Bookkeeping, not a preference: it has no UI and
    /// exists so the choice is applied on a transition instead of on every launch.
    static let appliedOwnerKey = "settings.snapEdgeOwnerApplied"
    private static let log = AppLogger(category: "SystemWindowTiling")

    /// Drag a window to a screen edge to tile it.
    static var isEdgeDragEnabled: Bool { flag(edgeDragKey) }
    /// Drag a window to the top of the screen to fill it.
    static var isTopEdgeDragEnabled: Bool { flag(topEdgeDragKey) }

    /// Whether macOS has its own drag-to-edge tiling at all.
    ///
    /// Before macOS 15 there is nothing to hand the gesture to, so the ownership choice does not
    /// exist there and must not be offered: picking macOS on such a machine would leave the gesture
    /// with no implementation at all.
    static var isAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    @discardableResult
    static func setEdgeDragEnabled(_ enabled: Bool) -> Bool { set(enabled, forKey: edgeDragKey) }

    @discardableResult
    static func setTopEdgeDragEnabled(_ enabled: Bool) -> Bool { set(enabled, forKey: topEdgeDragKey) }

    // MARK: - Ownership

    /// Mirrors an ownership choice onto macOS' two switches.
    ///
    /// `.lightStats` turns both off, so only the engine acts on the gesture; `.system` turns both on
    /// and leaves the whole gesture — sides, corners, and the menu bar — to macOS.
    static func apply(_ owner: SnapEdgeOwner) {
        let desired = switches(for: owner)
        setEdgeDragEnabled(desired.edgeDrag)
        setTopEdgeDragEnabled(desired.topEdgeDrag)
    }

    /// The switch state each owner requires, kept pure so the handover contract is testable without
    /// writing to the machine's own window-manager domain.
    static func switches(for owner: SnapEdgeOwner) -> (edgeDrag: Bool, topEdgeDrag: Bool) {
        switch owner {
        case .lightStats: return (edgeDrag: false, topEdgeDrag: false)
        case .system: return (edgeDrag: true, topEdgeDrag: true)
        }
    }

    /// Applies the ownership choice once per transition, and never twice for the same one.
    ///
    /// Safe to call on every configuration change: a user who turns one of the system switches on by
    /// hand while Light Stats owns the gesture keeps that setting, and Settings reports the conflict
    /// instead of silently reverting them on the next unrelated toggle. `apply` is injected so the
    /// rule can be tested without writing to the machine's real window-manager domain.
    static func reconcile(
        owner: SnapEdgeOwner,
        defaults: UserDefaults = .standard,
        apply: (SnapEdgeOwner) -> Void = SystemWindowTilingSetting.apply
    ) {
        guard #available(macOS 15.0, *) else { return }
        let applied = defaults.string(forKey: appliedOwnerKey).flatMap(SnapEdgeOwner.init(rawValue:))
        guard applied != owner else { return }
        defaults.set(owner.rawValue, forKey: appliedOwnerKey)
        apply(owner)
        DiagnosticLogService.record(
            category: "windowManagement",
            action: "systemTilingReconciled",
            fields: ["owner": owner.rawValue]
        )
    }

    /// Absent means macOS is using its own default, which ships enabled.
    private static func flag(_ key: String) -> Bool {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool else {
            return true
        }
        return value
    }

    private static func set(_ enabled: Bool, forKey key: String) -> Bool {
        CFPreferencesSetAppValue(key as CFString, enabled as CFBoolean, domain as CFString)
        let synchronized = CFPreferencesAppSynchronize(domain as CFString)
        log.info("System window tiling \(key) set to \(enabled), synchronized=\(synchronized)")

        DiagnosticLogService.record(
            category: "windowManagement",
            action: "systemTilingChanged",
            fields: ["key": key, "enabled": enabled ? "true" : "false", "synchronized": synchronized ? "true" : "false"]
        )
        return synchronized
    }
}
