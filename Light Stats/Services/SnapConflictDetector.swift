//
//  SnapConflictDetector.swift
//  Light Stats
//

import AppKit

/// Detects other window managers that are running.
///
/// Wins ships a blacklist of apps whose windows it refuses to touch; this is the mirror image. Two
/// window managers both listening for a drag to a screen edge produce a result that depends on
/// whichever moved the window last, which is indistinguishable from a bug. The user cannot be
/// expected to work that out, so the settings page says it.
///
/// Detection is best-effort by bundle identifier: an app that is not in the list is simply not
/// reported. That is the right failure direction — a missed warning is silent, a wrong one is
/// noise.
enum SnapConflictDetector {

    /// Known window managers, by bundle identifier.
    static let knownManagers: [String: String] = [
        "com.manytricks.Moom": "Moom",
        "com.knollsoft.Rectangle": "Rectangle",
        "com.knollsoft.RectanglePro": "Rectangle Pro",
        "com.crowdcafe.windowmagnet": "Magnet",
        "com.hegenberg.BetterSnapTool": "BetterSnapTool",
        "com.hegenberg.BetterTouchTool": "BetterTouchTool",
        "com.divisiblebyzero.Spectacle": "Spectacle",
        "com.irradiatedsoftware.SizeUp": "SizeUp",
        "cools.wins.main": "Wins",
        "com.prosofteng.WindowSwitcher": "WindowSwitcher"
    ]

    /// Names of conflicting managers that are running right now, other than ourselves.
    static func runningConflictNames() -> [String] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications
        var names: Set<String> = []
        for application in running {
            guard application.processIdentifier != selfPID,
                  let bundleID = application.bundleIdentifier,
                  let name = knownManagers[bundleID] else { continue }
            names.insert(name)
        }
        return names.sorted()
    }
}
