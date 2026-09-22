//
//  DockHoverPolicy.swift
//  Light Stats
//

/// What a settled pointer on a Dock icon means for the preview.
///
/// Pure and time-free: it takes the dwell time as a number rather than reading a clock, so the two
/// timings that decide the whole interaction — how long before the panel appears, and how long
/// before its thumbnails start loading — are covered by tests instead of by hovering icons.
///
/// The one rule that matters most is what is *not* here: moving from one icon to another is not an
/// exit. One panel holds one Dock item's contents at a time and swaps them, and the hide delay
/// only runs once the pointer has left the Dock,
/// which is why travelling along the Dock reads as the preview following the pointer rather than as
/// the preview closing and re-opening. So the monitor asks this type only what to do about the icon
/// under the pointer, and dismissal stays a separate decision made when the pointer leaves.
nonisolated enum DockHoverPolicy {

    /// How long the pointer must rest on an icon before the preview appears.
    static let hoverDelay: Double = 0.18
    /// How long it must rest before the icon's thumbnails start loading, so a panel that appears
    /// 120 ms later arrives with pictures instead of placeholders. Shorter than `hoverDelay` on
    /// purpose: travelling across the Dock must not start a capture for every icon it crosses.
    static let warmDelay: Double = 0.06

    /// The icon the pointer is currently resting on, and how long it has been there.
    struct State: Equatable {
        var candidate: DockHoverTarget?
        var candidateSince: Double = 0
        /// Whether this candidate's thumbnails have been requested. Once per candidate, never once
        /// per poll.
        var didWarm = false

        static let idle = State()
    }

    enum Action: Equatable {
        case idle
        /// Load this application's thumbnails; the panel is not shown yet.
        case warm(DockHoverTarget)
        /// Show this application's preview.
        case show(DockHoverTarget)
    }

    /// The pointer is inside the Dock and resting on `target` at `now`.
    ///
    /// - Parameter presented: the application whose preview is on screen, if any. It is what makes
    ///   a settled pointer on a *different* icon a transition rather than a first appearance.
    static func settled(
        _ state: inout State,
        presented: DockHoverTarget?,
        target: DockHoverTarget,
        now: Double
    ) -> Action {
        if state.candidate?.processID != target.processID {
            state.candidate = target
            state.candidateSince = now
            state.didWarm = false
            return .idle
        }
        let dwell = now - state.candidateSince
        if !state.didWarm, dwell >= warmDelay {
            state.didWarm = true
            return .warm(target)
        }
        guard presented?.processID != target.processID, dwell >= hoverDelay else { return .idle }
        return .show(target)
    }
}
