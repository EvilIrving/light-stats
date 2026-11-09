//
//  TCCGrantResult.swift
//  Light Stats
//

import Foundation

/// The typed outcome of the drag-to-grant flow.
nonisolated enum TCCGrantResult: Sendable, Equatable {
    /// The permission API now reads `true`.
    case granted
    /// The user finished in System Settings but this process still reads `false`.
    ///
    /// For Screen Recording this is not a failure: `CGPreflightScreenCaptureAccess()` caches its
    /// answer for the life of the process, so a real grant is *indistinguishable* from a refusal
    /// here, and the only honest thing to say is "if you allowed it, restart".
    case finishedInSettings
    /// Nothing concluded. Usually the user wandered off, or System Settings never opened.
    case timedOut

    /// Stable name for the diagnostic journal, so a support report can be read without decoding a
    /// Swift case name on the other end of a release boundary.
    var diagnosticName: String {
        switch self {
        case .granted: return "granted"
        case .finishedInSettings: return "finishedInSettings"
        case .timedOut: return "timedOut"
        }
    }
}

extension TCCGrantResult {

    /// The whole decision table, in one place.
    ///
    /// The final read always wins: `granted` is `granted` whichever signal brought us here, so a
    /// user who flips the switch and never closes the sheet is still recognised. The signal only
    /// decides what a `false` read means — the user finished in System Settings, or nothing
    /// happened at all.
    static func resolve(_ signal: TCCGrantSignal, isGranted: Bool) -> TCCGrantResult {
        if isGranted { return .granted }
        switch signal {
        case .settingsDismissed, .appReactivated:
            return .finishedInSettings
        case .timedOut:
            return .timedOut
        }
    }
}
