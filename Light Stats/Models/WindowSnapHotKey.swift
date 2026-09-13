//
//  WindowSnapHotKey.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import Foundation

/// One global shortcut registration: a Carbon key code + modifier mask bound to a snap action.
struct WindowSnapHotKey: Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var action: WindowSnapAction
}
