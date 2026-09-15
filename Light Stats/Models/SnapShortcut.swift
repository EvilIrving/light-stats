//
//  SnapShortcut.swift
//  Light Stats
//

import Foundation

/// A user-recordable global shortcut for one snap target.
///
/// Wins records shortcuts with the `KeyboardShortcuts` package; this project already has a working
/// recorder for the cleanup panel, so the same mechanic is generalized rather than adding a
/// dependency. Key code and modifier mask are Carbon's own values, kept as `UInt32` so the model
/// stays free of Carbon.
///
/// The target can be an action *or* a region, which is what lets a shortcut point at a layout the
/// user drew themselves. Wins has the same reach; a fixed enum of 19 actions does not.
struct SnapShortcut: Codable, Hashable, Sendable, Identifiable {

    var target: SnapTarget
    var keyCode: UInt32
    var modifiers: UInt32

    /// Shortcuts are keyed by what they do, so rebinding the same target replaces the old binding
    /// instead of leaving two registrations that fight over the same action.
    var id: SnapTarget { target }

    /// A shortcut with no key recorded. Rows exist for every action whether or not they are bound,
    /// so this — rather than a separate flag — is what "not set" means. One fewer field to keep
    /// consistent, and no state where a recorded key is present but switched off by accident.
    var isBound: Bool { keyCode != 0 || modifiers != 0 }

    init(target: SnapTarget, keyCode: UInt32, modifiers: UInt32) {
        self.target = target
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(action: WindowSnapAction, keyCode: UInt32, modifiers: UInt32) {
        self.init(target: .action(action), keyCode: keyCode, modifiers: modifiers)
    }

    /// The shortcut as a Carbon hotkey registration.
    var hotKey: WindowSnapHotKey {
        WindowSnapHotKey(keyCode: keyCode, modifiers: modifiers, target: target)
    }
}
