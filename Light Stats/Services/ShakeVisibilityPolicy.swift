//
//  ShakeVisibilityPolicy.swift
//  Light Stats
//

nonisolated enum ShakeVisibilityPolicy {

    /// Shake toggles the applications this service owns, including hides from its shortcuts.
    /// Apps already hidden before our request are never adopted into the restore history.
    static func command(hasHiddenApplications: Bool) -> WindowVisibilityCommand {
        hasHiddenApplications ? .restore : .hideOthers
    }
}
