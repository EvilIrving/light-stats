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

    /// Turns the system's edge-drag tiling on the first time window management is enabled.
    ///
    /// Our own swipe gesture can only guess which part of a window is its titlebar; the system's
    /// drag-to-edge path needs no guess at all, so it is the route a user should have working by
    /// default. This runs once per install and never fights the user afterwards — if they switch it
    /// back off, that choice stays.
    ///
    /// The bookkeeping flag is deliberately not a `SettingsManager` preference: it has no UI and
    /// represents a one-time migration, not a user choice.
    static func applyDefaultEdgeDragIfNeeded(defaults: UserDefaults = .standard) {
        guard #available(macOS 15.0, *) else { return }
        let appliedKey = "settings.systemTilingEdgeDragDefaultApplied"
        guard !defaults.bool(forKey: appliedKey) else { return }
        defaults.set(true, forKey: appliedKey)

        guard !SystemWindowTilingSetting.isEdgeDragEnabled else { return }
        SystemWindowTilingSetting.setEdgeDragEnabled(true)
    }
}
