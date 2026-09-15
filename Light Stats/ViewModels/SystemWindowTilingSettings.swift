//
//  SystemWindowTilingSettings.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import Combine
import Foundation
import OSLog

/// Observable facade over the system's own window-tiling switches.
///
/// These live in `com.apple.WindowManager`, not in our defaults. The system stays the source of
/// truth: mirroring the value into `SettingsManager` would let the two drift apart the moment the
/// user flips the switch in System Settings.
@MainActor
final class SystemWindowTilingSettings: ObservableObject {

    @Published var edgeDragEnabled: Bool {
        didSet {
            guard edgeDragEnabled != oldValue else { return }
            SystemWindowTilingSetting.setEdgeDragEnabled(edgeDragEnabled)
        }
    }

    @Published var topEdgeDragEnabled: Bool {
        didSet {
            guard topEdgeDragEnabled != oldValue else { return }
            SystemWindowTilingSetting.setTopEdgeDragEnabled(topEdgeDragEnabled)
        }
    }

    init() {
        edgeDragEnabled = SystemWindowTilingSetting.isEdgeDragEnabled
        topEdgeDragEnabled = SystemWindowTilingSetting.isTopEdgeDragEnabled
    }

    /// Re-reads the system values, for the case where the user changed them elsewhere.
    func reload() {
        edgeDragEnabled = SystemWindowTilingSetting.isEdgeDragEnabled
        topEdgeDragEnabled = SystemWindowTilingSetting.isTopEdgeDragEnabled
    }

    /// Settles the one-time conflict between the system's edge-drag tiling and ours.
    ///
    /// Both act on the same gesture. While both are live, the system tiles the window at the same
    /// moment the engine places it, and which one wins depends on which finished last — so exactly
    /// one has to own the gesture, and while our drag pipeline is on that has to be us.
    ///
    /// This runs once per install. After that the user's own choice stands, even if it reintroduces
    /// the conflict: the Settings page says so explicitly rather than silently correcting them.
    ///
    /// The bookkeeping flag is deliberately not a `SettingsManager` preference — it has no UI and
    /// represents a migration, not a choice.
    static func applyInitialEdgeDragPolicy(ownsEdgeSnapping: Bool, defaults: UserDefaults = .standard) {
        guard #available(macOS 15.0, *) else { return }
        let appliedKey = "settings.systemTilingEdgeDragDefaultApplied"
        guard !defaults.bool(forKey: appliedKey) else { return }
        defaults.set(true, forKey: appliedKey)

        let desired = !ownsEdgeSnapping
        guard SystemWindowTilingSetting.isEdgeDragEnabled != desired else { return }
        SystemWindowTilingSetting.setEdgeDragEnabled(desired)
        DiagnosticLogService.record(
            category: "windowManagement",
            action: "systemTilingReconciled",
            fields: ["edgeDrag": desired ? "true" : "false"]
        )
    }
}
