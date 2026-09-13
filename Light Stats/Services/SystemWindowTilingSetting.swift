//
//  SystemWindowTilingSetting.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import Foundation
import OSLog

/// macOS' own drag-to-edge tiling, surfaced instead of reimplemented.
///
/// "Drag a window to a screen edge to tile it" is the one gesture model that cannot misfire — the
/// drag *is* the intent, so there is no titlebar to identify and no control to mistake for one.
/// Light Stats does not duplicate it; it reads and writes the switch macOS keeps in the
/// `com.apple.WindowManager` domain so the capability stays reachable and can be turned on for the
/// user once, without hunting through System Settings.
enum SystemWindowTilingSetting {

    private static let domain = "com.apple.WindowManager"
    private static let edgeDragKey = "EnableTilingByEdgeDrag"
    private static let topEdgeDragKey = "EnableTopTilingByEdgeDrag"
    private static let log = AppLogger(category: "SystemWindowTiling")

    /// Drag a window to a screen edge to tile it.
    static var isEdgeDragEnabled: Bool { flag(edgeDragKey) }
    /// Drag a window to the top of the screen to fill it.
    static var isTopEdgeDragEnabled: Bool { flag(topEdgeDragKey) }

    @discardableResult
    static func setEdgeDragEnabled(_ enabled: Bool) -> Bool { set(enabled, forKey: edgeDragKey) }

    @discardableResult
    static func setTopEdgeDragEnabled(_ enabled: Bool) -> Bool { set(enabled, forKey: topEdgeDragKey) }

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
