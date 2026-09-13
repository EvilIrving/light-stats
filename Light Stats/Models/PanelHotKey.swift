//
//  PanelHotKey.swift
//  Light Stats
//
//  User-recorded global shortcut that summons the cleanup panel at the pointer.
//

import Foundation

/// Carbon virtual-key + modifier mask for the cleanup-panel shortcut.
///
/// Modifier bits match `FindMouseTriggerKey` so a recorder can share the same flag layout.
/// Conversion to Carbon `cmdKey` / `controlKey` / … happens in `PanelHotKeyService`.
struct PanelHotKey: Hashable, RawRepresentable, Sendable {
    static let controlModifier: UInt8 = 1 << 0
    static let optionModifier: UInt8 = 1 << 1
    static let shiftModifier: UInt8 = 1 << 2
    static let commandModifier: UInt8 = 1 << 3

    /// `kVK_ANSI_U` (0x20). Default combo is ⌃⌥⌘U — does not collide with window-snap ⌃⌥C.
    static let `default` = PanelHotKey(
        keyCode: 32,
        modifiers: controlModifier | optionModifier | commandModifier,
        displayKey: "U"
    )

    var keyCode: UInt32
    var modifiers: UInt8
    var displayKey: String

    init(keyCode: UInt32, modifiers: UInt8, displayKey: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayKey = displayKey
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == "v1",
              let keyCode = UInt32(parts[1]),
              let modifiers = UInt8(parts[2]),
              !parts[3].isEmpty else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, displayKey: String(parts[3]))
    }

    var rawValue: String {
        "v1|\(keyCode)|\(modifiers)|\(displayKey)"
    }

    var modifierSymbols: String {
        var result = ""
        if modifiers & Self.controlModifier != 0 { result += "⌃" }
        if modifiers & Self.optionModifier != 0 { result += "⌥" }
        if modifiers & Self.shiftModifier != 0 { result += "⇧" }
        if modifiers & Self.commandModifier != 0 { result += "⌘" }
        return result
    }

    var displayTitle: String { modifierSymbols + displayKey }

    var hasModifier: Bool { modifiers != 0 }
}
