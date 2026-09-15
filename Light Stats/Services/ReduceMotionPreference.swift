//
//  ReduceMotionPreference.swift
//  Light Stats
//

import AppKit

/// Whether the system is asking for reduced motion.
///
/// Read through `NSWorkspace` on every query rather than cached: the user can flip the switch in
/// System Settings and the very next animation should already respect it.
///
/// Reduced motion is **not** "no animation". Wins keeps a shorter timeline and so does this — an
/// instant jump reads as a glitch, whereas a short one still reads as a deliberate movement.
@MainActor
enum ReduceMotionPreference {

    static var isEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
