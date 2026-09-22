//
//  DockClickPolicy.swift
//  Light Stats
//

import CoreGraphics
import Foundation

/// What a completed click on a Dock icon should do.
///
/// This is the whole decision of the Dock-click feature, and it is deliberately asymmetric: macOS
/// already activates a non-frontmost app and already brings back a minimized window when its icon is
/// clicked. The only thing the system does *not* do is put the frontmost app's windows away, which is
/// the half that makes the gesture a toggle instead of a dead click. So the rule is "collapse the
/// frontmost app that is showing windows, restore what we collapsed, otherwise let the Dock be".
nonisolated enum DockClickAction: Equatable, Sendable {
    case collapse(pid_t)
    case restore(pid_t)
    /// Nothing to do; `reason` is a stable code for the diagnostic journal.
    case pass(reason: String)
}

/// The facts a click is judged on, all of them captured *before* the mouse went down.
///
/// Capturing before the click matters: the Dock changes the world while handling the click, so a
/// state read afterwards cannot tell "this app was already showing windows" from "the Dock just
/// brought them forward".
nonisolated struct DockClickCandidate: Equatable, Sendable {
    var processID: pid_t
    var bundleIdentifier: String?
    var name: String
    var isOwnApplication: Bool
    var isRunning: Bool
    var isRegular: Bool
    /// The clicked app was the frontmost one when the mouse went down.
    var wasFrontmost: Bool
    /// At least one standard window is on screen (not minimized), full screen included.
    var hasVisibleWindows: Bool
    /// At least one window could actually be minimized: not already minimized, not full screen.
    ///
    /// A full-screen window cannot be minimized by macOS, so an app showing only a full-screen window
    /// has nothing to collapse — and pretending otherwise would swallow the click for no result.
    var hasCollapsibleWindows: Bool
    /// At least one window is minimized right now.
    ///
    /// This is what makes "bring them back" honest: a record plus minimized windows means the click is
    /// the way out, while a record with nothing minimized means those windows are gone (the user closed
    /// them) and there is nothing left to restore.
    var hasMinimizedWindows: Bool

    static let unknown = DockClickCandidate(
        processID: 0,
        bundleIdentifier: nil,
        name: "",
        isOwnApplication: false,
        isRunning: false,
        isRegular: false,
        wasFrontmost: false,
        hasVisibleWindows: false,
        hasCollapsibleWindows: false,
        hasMinimizedWindows: false
    )
}

nonisolated enum DockClickPolicy {

    /// Milliseconds a pending click stays valid. A Dock click is a fast gesture; anything slower is
    /// a press-and-hold (the Dock's own menu) and must not toggle windows when it ends.
    static let clickValidity: TimeInterval = 0.6
    /// How far the pointer may travel during the click and still count as a click. Dragging a Dock
    /// icon rearranges it; that drag must never collapse windows.
    static let movementTolerance: CGFloat = 6
    /// A second click on the same icon inside this window is treated as the tail of the first one, so
    /// a double click does not collapse and immediately restore.
    static let repeatTolerance: TimeInterval = 0.35

    static func action(for candidate: DockClickCandidate, isCollapsedByUs: Bool) -> DockClickAction {
        guard candidate.isRunning else { return .pass(reason: "not-running") }
        guard candidate.isRegular else { return .pass(reason: "not-a-dock-app") }
        guard !candidate.isOwnApplication else { return .pass(reason: "own-app") }

        // We put these windows away and they are still away: this click is the way back. Checked
        // before the collapse branch because a collapsed app is still frontmost.
        if isCollapsedByUs, candidate.hasMinimizedWindows {
            return .restore(candidate.processID)
        }
        // We put them away and now Accessibility reports no windows at all. That is the common case in
        // practice — many apps stop publishing a minimized window through `AXWindows`, and the Dock
        // brings it back on this very click by itself — so the record has nothing left to own.
        if isCollapsedByUs, !candidate.hasVisibleWindows {
            return .pass(reason: "windows-away")
        }
        guard candidate.wasFrontmost else { return .pass(reason: "not-frontmost") }
        guard candidate.hasCollapsibleWindows else {
            guard candidate.hasVisibleWindows else { return .pass(reason: "no-windows") }
            return .pass(reason: "only-full-screen")
        }
        return .collapse(candidate.processID)
    }

    /// Whether this click is a repeat of an action we just took.
    static func isRepeat(since lastAction: DockClickMoment?, processID: pid_t, at now: TimeInterval) -> Bool {
        guard let lastAction, lastAction.processID == processID else { return false }
        return now - lastAction.at < repeatTolerance
    }
}

/// The last action the feature took, for repeat suppression.
nonisolated struct DockClickMoment: Equatable, Sendable {
    var processID: pid_t
    var at: TimeInterval
}

/// A click in progress: mouse down, optional travel, mouse up.
///
/// Pure and clock-free — the caller passes the time — so "a drag is not a click" and "a hold is not a
/// click" are testable without a mouse. The geometry lives here and the icon resolution lives in the
/// service, because resolving an icon is Accessibility work while judging the gesture is arithmetic.
nonisolated struct DockClickGesture: Equatable {
    private(set) var downPoint: CGPoint?
    private(set) var startedAt: TimeInterval = 0

    var isPending: Bool { downPoint != nil }

    mutating func begins(at point: CGPoint, now: TimeInterval) {
        downPoint = point
        startedAt = now
    }

    /// The pointer moved while the button is down. A Dock icon drag (rearranging the Dock, dropping
    /// onto a stack) travels, and that is not a click any more.
    mutating func moved(to point: CGPoint) -> Bool {
        guard let downPoint else { return false }
        guard hypot(point.x - downPoint.x, point.y - downPoint.y) > DockClickPolicy.movementTolerance else {
            return false
        }
        cancel()
        return true
    }

    /// The button came up: whether the whole gesture was still a click.
    mutating func ends(at point: CGPoint, now: TimeInterval) -> Bool {
        defer { cancel() }
        guard let downPoint else { return false }
        guard now - startedAt <= DockClickPolicy.clickValidity else { return false }
        return hypot(point.x - downPoint.x, point.y - downPoint.y) <= DockClickPolicy.movementTolerance
    }

    mutating func cancel() {
        downPoint = nil
        startedAt = 0
    }
}
