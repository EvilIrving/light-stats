//
//  FindMouseTriggerKey.swift
//  Light Stats
//
//  User-recorded keyboard trigger for Find My Mouse.
//

import Foundation

nonisolated struct FindMouseTriggerKey: Hashable, RawRepresentable, Sendable {
    static let controlModifier: UInt8 = 1 << 0
    static let optionModifier: UInt8 = 1 << 1
    static let shiftModifier: UInt8 = 1 << 2
    static let commandModifier: UInt8 = 1 << 3
    static let functionModifier: UInt8 = 1 << 4

    static let leftControl = modifier(keyCode: 59, modifiers: controlModifier, symbol: "⌃")
    static let leftOption = modifier(keyCode: 58, modifiers: optionModifier, symbol: "⌥")
    static let leftCommand = modifier(keyCode: 55, modifiers: commandModifier, symbol: "⌘")
    static let leftShift = modifier(keyCode: 56, modifiers: shiftModifier, symbol: "⇧")
    static let rightControl = modifier(keyCode: 62, modifiers: controlModifier, symbol: "⌃")
    static let rightOption = modifier(keyCode: 61, modifiers: optionModifier, symbol: "⌥")
    static let rightCommand = modifier(keyCode: 54, modifiers: commandModifier, symbol: "⌘")
    static let rightShift = modifier(keyCode: 60, modifiers: shiftModifier, symbol: "⇧")
    static let function = modifier(keyCode: 63, modifiers: functionModifier, symbol: "fn")

    let keyCode: Int64
    let modifiers: UInt8
    let displayKey: String
    let isModifierOnly: Bool

    init(keyCode: Int64, modifiers: UInt8, displayKey: String, isModifierOnly: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayKey = displayKey
        self.isModifierOnly = isModifierOnly
    }

    init?(rawValue: String) {
        switch rawValue {
        case "leftControl": self = .leftControl
        case "leftOption": self = .leftOption
        case "leftCommand": self = .leftCommand
        case "leftShift": self = .leftShift
        case "rightControl": self = .rightControl
        case "rightOption": self = .rightOption
        case "rightCommand": self = .rightCommand
        case "rightShift": self = .rightShift
        case "function": self = .function
        default:
            let parts = rawValue.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5,
                  parts[0] == "v1",
                  let keyCode = Int64(parts[1]),
                  let modifiers = UInt8(parts[2]),
                  let modifierFlag = UInt8(parts[3]),
                  modifierFlag <= 1,
                  !parts[4].isEmpty else { return nil }
            self.init(
                keyCode: keyCode,
                modifiers: modifiers,
                displayKey: String(parts[4]),
                isModifierOnly: modifierFlag == 1
            )
        }
    }

    var rawValue: String {
        if isModifierOnly {
            switch keyCode {
            case 59: return "leftControl"
            case 58: return "leftOption"
            case 55: return "leftCommand"
            case 56: return "leftShift"
            case 62: return "rightControl"
            case 61: return "rightOption"
            case 54: return "rightCommand"
            case 60: return "rightShift"
            case 63: return "function"
            default: break
            }
        }
        return "v1|\(keyCode)|\(modifiers)|\(isModifierOnly ? 1 : 0)|\(displayKey)"
    }

    var modifierSymbols: String {
        var result = ""
        if modifiers & Self.controlModifier != 0 { result += "⌃" }
        if modifiers & Self.optionModifier != 0 { result += "⌥" }
        if modifiers & Self.shiftModifier != 0 { result += "⇧" }
        if modifiers & Self.commandModifier != 0 { result += "⌘" }
        if modifiers & Self.functionModifier != 0 { result += "fn" }
        return result
    }

    var isLeftModifier: Bool? {
        guard isModifierOnly else { return nil }
        switch keyCode {
        case 55, 56, 58, 59: return true
        case 54, 60, 61, 62: return false
        default: return nil
        }
    }

    static func modifierKey(keyCode: Int64) -> FindMouseTriggerKey? {
        switch keyCode {
        case leftControl.keyCode: return .leftControl
        case leftOption.keyCode: return .leftOption
        case leftCommand.keyCode: return .leftCommand
        case leftShift.keyCode: return .leftShift
        case rightControl.keyCode: return .rightControl
        case rightOption.keyCode: return .rightOption
        case rightCommand.keyCode: return .rightCommand
        case rightShift.keyCode: return .rightShift
        case function.keyCode: return .function
        default: return nil
        }
    }

    private static func modifier(keyCode: Int64, modifiers: UInt8, symbol: String) -> FindMouseTriggerKey {
        FindMouseTriggerKey(
            keyCode: keyCode,
            modifiers: modifiers,
            displayKey: symbol,
            isModifierOnly: true
        )
    }
}
