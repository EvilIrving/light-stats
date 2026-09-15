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
/// Light Stats now implements the same gesture itself, because the system's version has no gaps, no
/// custom layouts, and no island. Two implementations of one gesture cannot both be live: the
/// system would tile the window at the same moment the engine places it, and the result would
/// depend on which finished last. So the switch is surfaced here, the first time window management
/// is enabled the system's copy is turned off once, and the user's later choice is never overridden
/// again.
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
