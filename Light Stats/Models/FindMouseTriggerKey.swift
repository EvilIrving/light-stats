//
//  FindMouseTriggerKey.swift
//  Light Stats
//
//  Left-modifier trigger for Find My Mouse. Right modifiers are omitted
//  because they are commonly remapped.
//

import Foundation

nonisolated enum FindMouseTriggerKey: String, CaseIterable, Sendable {
    case leftControl
    case leftOption
    case leftCommand
    case leftShift

    /// CGEvent key codes: kVK_Control / kVK_Option / kVK_Command / kVK_Shift.
    var keyCode: Int64 {
        switch self {
        case .leftControl: return 59
        case .leftOption: return 58
        case .leftCommand: return 55
        case .leftShift: return 56
        }
    }

    /// Segmented-picker labels. Modifier glyphs are language-neutral.
    var symbol: String {
        switch self {
        case .leftControl: return "⌃"
        case .leftOption: return "⌥"
        case .leftCommand: return "⌘"
        case .leftShift: return "⇧"
        }
    }
}
