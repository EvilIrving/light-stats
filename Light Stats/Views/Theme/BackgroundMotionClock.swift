//
//  BackgroundMotionClock.swift
//  Light Stats
//

import Combine
import Foundation

/// Integrates wall time into a continuous theme-neutral scene timeline.
@MainActor
final class BackgroundMotionClock: ObservableObject {
    struct Sample: Equatable, Sendable {
        let time: TimeInterval
        let isPaused: Bool
        let intensity: Double
        let sceneSeed: UInt64
    }

    @Published private(set) var normalizedIntensity: Double

    private var accumulatedTime: TimeInterval = 0
    private var lastDate: Date
    private var frozenIntensity: Double
    private let sceneSeed: UInt64

    var isPaused: Bool { normalizedIntensity == 0 }

    init(
        intensity: Double,
        startDate: Date = Date(),
        sceneSeed: UInt64 = UInt64.random(in: UInt64.min ... UInt64.max)
    ) {
        let normalizedIntensity = Self.normalize(intensity)
        self.normalizedIntensity = normalizedIntensity
        self.frozenIntensity = normalizedIntensity
        self.lastDate = startDate
        self.sceneSeed = sceneSeed
    }

    func sample(at date: Date) -> Sample {
        advance(to: date)
        return Sample(
            time: accumulatedTime,
            isPaused: isPaused,
            intensity: isPaused ? frozenIntensity : normalizedIntensity,
            sceneSeed: sceneSeed
        )
    }

    func setIntensity(_ intensity: Double, at date: Date = Date()) {
        advance(to: date)
        let nextIntensity = Self.normalize(intensity)
        guard nextIntensity != normalizedIntensity else { return }
        if nextIntensity == 0 {
            frozenIntensity = normalizedIntensity
        } else {
            frozenIntensity = nextIntensity
        }
        normalizedIntensity = nextIntensity
    }

    private func advance(to date: Date) {
        let elapsed = max(0, date.timeIntervalSince(lastDate))
        accumulatedTime += elapsed * timeScale
        lastDate = date
    }

    private var timeScale: Double {
        guard normalizedIntensity > 0 else { return 0 }
        let smoothIntensity = normalizedIntensity * normalizedIntensity * (3 - 2 * normalizedIntensity)
        return 0.08 + smoothIntensity * 0.92
    }

    private static func normalize(_ intensity: Double) -> Double {
        guard intensity.isFinite else { return 0 }
        return min(max(intensity, 0), 1)
    }
}
