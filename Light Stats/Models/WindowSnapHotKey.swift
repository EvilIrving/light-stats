//
//  WindowSnapHotKey.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import Foundation

/// One global shortcut registration: a Carbon key code + modifier mask bound to a snap target.
struct WindowSnapHotKey: Sendable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
    var target: SnapTarget

    init(keyCode: UInt32, modifiers: UInt32, target: SnapTarget) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.target = target
    }

    init(keyCode: UInt32, modifiers: UInt32, action: WindowSnapAction) {
        self.init(keyCode: keyCode, modifiers: modifiers, target: .action(action))
    }
}
