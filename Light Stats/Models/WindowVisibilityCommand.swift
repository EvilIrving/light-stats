//
//  WindowVisibilityCommand.swift
//  Light Stats
//

import Foundation

/// Hiding and restoring whole applications.
///
/// Separate from `WindowSnapAction` because these do not move anything: they act on applications,
/// not on geometry, and mixing them into the snap vocabulary would put three non-geometric
/// operations through an engine that exists to compute rectangles.
enum WindowVisibilityCommand: String, Codable, Sendable, CaseIterable, Identifiable {

    /// Hide every other application, keeping the one that triggered it.
    case hideOthers
    /// Hide everything, including the frontmost application.
    case hideAll
    /// Bring back whatever this app hid — and nothing else.
    case restore

    var id: String { rawValue }

    var titleKey: String { "window.visibility.\(rawValue)" }

    /// `restore` is the only one that is meaningless when nothing was hidden.
    var requiresHiddenApplications: Bool { self == .restore }
}
