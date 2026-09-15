//
//  WindowSnapKeyCode.swift
//  Light Stats
//

import Foundation

/// Carbon virtual key codes and modifier masks, as plain numbers.
///
/// The model layer stores these values and never imports Carbon; the services convert them back to
/// `UInt32` for `RegisterEventHotKey`, which takes exactly these numbers anyway.
enum WindowSnapKeyCode {

    static let leftArrow: UInt32 = 123
    static let rightArrow: UInt32 = 124
    static let downArrow: UInt32 = 125
    static let upArrow: UInt32 = 126
    static let `return`: UInt32 = 36
    static let c: UInt32 = 8
    static let escape: UInt32 = 53

    static let command: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12

    /// Human-readable name for a key code, used by the recorder's button label.
    ///
    /// Only the keys a person is likely to bind are named; anything else falls back to a
    /// glyph-plus-code form rather than pretending to know what the key is called.
    static func keyLabel(for keyCode: UInt32) -> String? {
        labels[keyCode]
    }

    /// `⌃⌥⇧⌘` in the order macOS renders them.
    static func modifierLabel(_ modifiers: UInt32) -> String {
        var label = ""
        if modifiers & control != 0 { label += "⌃" }
        if modifiers & option != 0 { label += "⌥" }
        if modifiers & shift != 0 { label += "⇧" }
        if modifiers & command != 0 { label += "⌘" }
        return label
    }

    static func displayTitle(keyCode: UInt32, modifiers: UInt32) -> String {
        let modifiersText = modifierLabel(modifiers)
        let key = keyLabel(for: keyCode) ?? "⌨︎\(keyCode)"
        return modifiersText + key
    }

    private static let labels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "␣", 50: "`", 51: "⌫", 53: "⎋", 71: "⌧", 76: "↩",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "↖", 116: "⇞", 117: "⌦", 118: "F4", 119: "↘", 120: "F2",
        121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
