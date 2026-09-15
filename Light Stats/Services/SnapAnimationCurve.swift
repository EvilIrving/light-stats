//
//  SnapAnimationCurve.swift
//  Light Stats
//

import Foundation

/// Samples a timing into a 0…1 progress value. Pure, so the whole feel of the animation is
/// verifiable without a display.
nonisolated enum SnapAnimationCurve {

    /// Below this the transition is considered finished. `1 - progress` is the amplitude of the
    /// residual motion.
    static let settleTolerance: Double = 0.01

    /// Eased progress for a timing at `elapsed` seconds. May exceed 1 briefly for an underdamped
    /// spring, which is the intended overshoot; callers clamp only where a value must stay valid.
    static func progress(for timing: SnapTiming, at elapsed: TimeInterval) -> Double {
        switch timing {
        case .curve(let name, let duration):
            guard duration > 0 else { return 1 }
            let fraction = min(max(elapsed / duration, 0), 1)
            return curve(name, fraction)
        case .spring(let response, let dampingFraction):
            return springProgress(response: response, dampingFraction: dampingFraction, elapsed: elapsed)
        }
    }

    /// How long a timing runs for before it is visually done.
    ///
    /// Derived from the decay envelope `e^(-ζωt)` rather than a fixed multiplier, so a snappier
    /// spring really is shorter and a bouncier one really does take longer to settle.
    static func duration(for timing: SnapTiming) -> TimeInterval {
        switch timing {
        case .curve(_, let duration):
            return max(duration, 0)
        case .spring(let response, let dampingFraction):
            let frequency = 2 * Double.pi / max(response, 0.01)
            let damping = max(dampingFraction, 0.05)
            let settle = -log(settleTolerance) / (damping * frequency)
            return min(max(settle, 0.08), 1.5)
        }
    }

    // MARK: - Springs

    private static func springProgress(
        response: Double,
        dampingFraction: Double,
        elapsed: TimeInterval
    ) -> Double {
        guard response > 0 else { return 1 }
        let t = max(elapsed, 0)
        let frequency = 2 * Double.pi / response
        let damping = max(dampingFraction, 0.01)

        if abs(damping - 1) < 0.001 {
            let decay = exp(-frequency * t)
            return 1 - (1 + frequency * t) * decay
        }

        if damping < 1 {
            let dampedFrequency = frequency * (1 - damping * damping).squareRoot()
            let decay = exp(-damping * frequency * t)
            let envelope = cos(dampedFrequency * t) + damping * frequency / dampedFrequency * sin(dampedFrequency * t)
            return 1 - decay * envelope
        }

        let root = (damping * damping - 1).squareRoot()
        let decay = exp(-damping * frequency * t)
        let envelope = cosh(frequency * root * t) + damping / root * sinh(frequency * root * t)
        return 1 - decay * envelope
    }

    // MARK: - Curves

    private static func curve(_ name: SnapCurve, _ t: Double) -> Double {
        switch name {
        case .linear:
            return t
        case .easeOut:
            // Cubic ease-out: fast start, long settle.
            let inverse = 1 - t
            return 1 - inverse * inverse * inverse
        case .easeInOut:
            return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        }
    }
}
