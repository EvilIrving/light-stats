//
//  DragShakeDetector.swift
//  Light Stats
//

import CoreGraphics

/// Recognises "shake the window sideways" while a drag is in progress.
///
/// Aero Shake, and Wins' `DragShakeChecker`. Pure and time-injected, so the whole gesture — how
/// many reversals, how fast, and how long before it can fire again — is covered by tests instead of
/// by waving a mouse at the screen.
///
/// The threshold is about *reversals*, not distance or speed. A drag that merely wobbles has one
/// direction change; a deliberate shake has several within a fraction of a second. Requiring
/// several is what keeps this from firing while somebody is carefully positioning a window.
nonisolated struct DragShakeDetector {

    struct Configuration: Sendable, Hashable {
        /// Horizontal travel in one direction that counts as "a shake stroke".
        var strokeDistance: CGFloat
        /// Direction changes needed to qualify.
        var minimumReversals: Int
        /// All of them must land inside this window.
        var window: TimeInterval
        /// Nothing may fire again until this long after a successful detection.
        var cooldown: TimeInterval

        static let `default` = Configuration(
            strokeDistance: 60,
            minimumReversals: 3,
            window: 0.7,
            cooldown: 1.2
        )
    }

    private let configuration: Configuration
    /// Horizontal distance accumulated since the last direction change.
    private var strokeDistance: CGFloat = 0
    /// Sign of the last qualified stroke: `1` right, `-1` left, `0` none yet.
    private var strokeDirection: Int = 0
    private var strokeTimestamps: [TimeInterval] = []
    private var lastDetection: TimeInterval = -.infinity

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// Feeds one horizontal movement sample.
    ///
    /// - Returns: `true` exactly once per shake, on the sample that completes it.
    mutating func update(horizontalDelta: CGFloat, at time: TimeInterval) -> Bool {
        guard time - lastDetection >= configuration.cooldown else { return false }

        strokeDistance += horizontalDelta
        guard abs(strokeDistance) >= configuration.strokeDistance else { return false }

        let direction = strokeDistance > 0 ? 1 : -1
        strokeDistance = 0

        if direction == strokeDirection {
            // Still the same stroke; nothing about it is a reversal.
            return false
        }
        strokeDirection = direction

        strokeTimestamps.append(time)
        // Anything older than the window cannot be part of *this* shake.
        strokeTimestamps.removeAll { time - $0 > configuration.window }

        guard strokeTimestamps.count >= configuration.minimumReversals else { return false }
        lastDetection = time
        reset()
        return true
    }

    /// Drops the in-progress gesture. Called when a drag starts or ends, so a shake can never be
    /// assembled from across two different drags.
    mutating func reset() {
        strokeDistance = 0
        strokeDirection = 0
        strokeTimestamps.removeAll()
    }
}
