//
//  SunGoldTreeShadowModel.swift
//  Light Stats
//

import CoreGraphics
import Foundation

/// Connected fine branches, clustered canopy masses, and light leaking through their gaps.
struct SunGoldTreeShadowModel: BackgroundOcclusionModel {
    let palette: SunGoldBackgroundTheme.Palette

    func makeOcclusions(
        time: TimeInterval,
        size: CGSize,
        configuration: BackgroundSceneConfiguration
    ) -> [BackgroundSceneFrame.Primitive] {
        let seed = configuration.sceneSeed
        let solarState = SunGoldPhysics.solarState(time: time, size: size, seed: seed)
        let gust = SunGoldPhysics.gust(at: time, seed: seed)
        return branchShadows(
            time: time,
            size: size,
            solarState: solarState,
            gust: gust,
            sceneSeed: seed
        ) + foliageShadows(
            time: time,
            size: size,
            solarState: solarState,
            gust: gust,
            sceneSeed: seed
        ) + lightFlecks(
            time: time,
            size: size,
            solarState: solarState,
            gust: gust,
            sceneSeed: seed
        )
    }

    private func branchShadows(
        time: TimeInterval,
        size: CGSize,
        solarState: SunGoldPhysics.SolarState,
        gust: CGFloat,
        sceneSeed: UInt64
    ) -> [BackgroundSceneFrame.Primitive] {
        let branchSeed = CoherentNoise.derivedSeed(sceneSeed, channel: 0x42_52_41_4E_43_48)
        let branchSway = CGFloat(CoherentNoise.fractal(
            at: time * 0.18,
            seed: branchSeed,
            octaves: 3,
            persistence: 0.48
        ))
        let scale = min(size.width, size.height)
        return Self.branches.map { segment in
            let start = projectedBranchPoint(
                segment.start,
                size: size,
                solarState: solarState,
                gust: gust,
                branchSway: branchSway
            )
            let end = projectedBranchPoint(
                segment.end,
                size: size,
                solarState: solarState,
                gust: gust,
                branchSway: branchSway
            )
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            let length = max(hypot(deltaX, deltaY), 1)
            let mask = BackgroundSceneFrame.SoftMask(
                center: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2),
                size: CGSize(width: scale * segment.thickness, height: length),
                angle: atan2(deltaY, deltaX) - .pi / 2,
                shape: .capsule,
                color: palette.treeShadow,
                opacity: min(segment.opacity * 1.75, 0.48),
                softness: scale * 0.002,
                blendMode: .multiply
            )
            return .softMask(mask)
        }
    }

    private func foliageShadows(
        time: TimeInterval,
        size: CGSize,
        solarState: SunGoldPhysics.SolarState,
        gust: CGFloat,
        sceneSeed: UInt64
    ) -> [BackgroundSceneFrame.Primitive] {
        var shadows: [BackgroundSceneFrame.Primitive] = []
        shadows.reserveCapacity(Self.foliageAnchors.count * Self.lobesPerCluster)
        for clusterIndex in Self.foliageAnchors.indices {
            let anchor = animatedFoliageAnchor(
                index: clusterIndex,
                time: time,
                size: size,
                solarState: solarState,
                gust: gust,
                sceneSeed: sceneSeed
            )
            for lobeIndex in 0..<Self.lobesPerCluster {
                shadows.append(foliageLobe(
                    clusterIndex: clusterIndex,
                    lobeIndex: lobeIndex,
                    time: time,
                    size: size,
                    anchor: anchor,
                    sceneSeed: sceneSeed
                ))
            }
        }
        return shadows
    }

    private func foliageLobe(
        clusterIndex: Int,
        lobeIndex: Int,
        time: TimeInterval,
        size: CGSize,
        anchor: CGPoint,
        sceneSeed: UInt64
    ) -> BackgroundSceneFrame.Primitive {
        let channel = UInt64(clusterIndex * Self.lobesPerCluster + lobeIndex)
        let seed = CoherentNoise.derivedSeed(sceneSeed, channel: 0x4C_45_41_46 + channel)
        let offsetX = CoherentNoise.value(at: 0.31, seed: seed)
        let offsetY = CoherentNoise.value(at: 1.43, seed: seed)
        let widthVariation = normalizedNoise(at: 2.57, seed: seed)
        let heightVariation = normalizedNoise(at: 3.69, seed: seed)
        let angleVariation = CoherentNoise.value(at: 4.81, seed: seed)
        let depth = normalizedNoise(at: 5.93, seed: seed)
        let flutter = CoherentNoise.fractal(
            at: time * (0.54 + depth * 0.72) + Double(lobeIndex) * 0.29,
            seed: CoherentNoise.derivedSeed(seed, channel: 1),
            octaves: 2,
            persistence: 0.60
        )
        let shimmer = CoherentNoise.fractal(
            at: time * (0.42 + depth * 0.84) + Double(clusterIndex) * 0.37,
            seed: CoherentNoise.derivedSeed(seed, channel: 2),
            octaves: 2,
            persistence: 0.64
        )
        let scale = min(size.width, size.height)
        let mask = BackgroundSceneFrame.SoftMask(
            center: CGPoint(
                x: anchor.x + CGFloat(offsetX) * scale * 0.085 + CGFloat(flutter) * scale * 0.008,
                y: anchor.y + CGFloat(offsetY) * scale * 0.070 + CGFloat(flutter) * scale * 0.006
            ),
            size: CGSize(
                width: scale * (0.055 + CGFloat(widthVariation) * 0.075),
                height: scale * (0.035 + CGFloat(heightVariation) * 0.050)
            ),
            angle: CGFloat(angleVariation) * 1.08 + CGFloat(flutter) * 0.24,
            shape: .leaf,
            color: palette.treeShadow,
            opacity: (0.15 + depth * 0.17) * (0.65 + (shimmer + 1) * 0.26),
            softness: scale * (0.0025 + CGFloat(1 - depth) * 0.0025),
            blendMode: .multiply
        )
        return .softMask(mask)
    }

    private func lightFlecks(
        time: TimeInterval,
        size: CGSize,
        solarState: SunGoldPhysics.SolarState,
        gust: CGFloat,
        sceneSeed: UInt64
    ) -> [BackgroundSceneFrame.Primitive] {
        (0..<Self.lightFleckCount).map { index in
            let clusterIndex = index % Self.foliageAnchors.count
            let anchor = animatedFoliageAnchor(
                index: clusterIndex,
                time: time,
                size: size,
                solarState: solarState,
                gust: gust,
                sceneSeed: sceneSeed
            )
            return lightFleck(
                index: index,
                time: time,
                size: size,
                anchor: anchor,
                sceneSeed: sceneSeed
            )
        }
    }

    private func lightFleck(
        index: Int,
        time: TimeInterval,
        size: CGSize,
        anchor: CGPoint,
        sceneSeed: UInt64
    ) -> BackgroundSceneFrame.Primitive {
        let seed = CoherentNoise.derivedSeed(sceneSeed, channel: 0x47_4C_49_4E_54 + UInt64(index))
        let offsetX = CoherentNoise.value(at: 0.73, seed: seed)
        let offsetY = CoherentNoise.value(at: 1.87, seed: seed)
        let sparkle = CoherentNoise.fractal(
            at: time * 1.34 + Double(index) * 0.41,
            seed: CoherentNoise.derivedSeed(seed, channel: 1),
            octaves: 2,
            persistence: 0.63
        )
        let scale = min(size.width, size.height)
        let sparkleStrength = pow((sparkle + 1) / 2, 2.2)
        let mask = BackgroundSceneFrame.SoftMask(
            center: CGPoint(
                x: anchor.x + CGFloat(offsetX) * scale * 0.075,
                y: anchor.y + CGFloat(offsetY) * scale * 0.060
            ),
            size: CGSize(
                width: scale * (0.016 + CGFloat(sparkleStrength) * 0.032),
                height: scale * (0.007 + CGFloat(sparkleStrength) * 0.014)
            ),
            angle: CGFloat(CoherentNoise.value(at: 3.11, seed: seed)) * 0.82,
            shape: .ellipse,
            color: palette.sunCore,
            opacity: 0.035 + sparkleStrength * 0.30,
            softness: scale * 0.003,
            blendMode: .plusLighter,
            role: .surfaceHighlight
        )
        return .softMask(mask)
    }

    private func animatedFoliageAnchor(
        index: Int,
        time: TimeInterval,
        size: CGSize,
        solarState: SunGoldPhysics.SolarState,
        gust: CGFloat,
        sceneSeed: UInt64
    ) -> CGPoint {
        let seed = CoherentNoise.derivedSeed(sceneSeed, channel: 0x43_41_4E_4F_50_59 + UInt64(index))
        let localSway = CGFloat(CoherentNoise.fractal(
            at: time * 0.27 + Double(index) * 0.19,
            seed: seed,
            octaves: 3,
            persistence: 0.52
        ))
        let anchor = Self.foliageAnchors[index]
        return CGPoint(
            x: size.width * (
                anchor.x + solarState.shadowDirection * 0.046 + gust * 0.016 + localSway * 0.010
            ),
            y: size.height * (anchor.y + localSway * 0.006)
        )
    }

    private func projectedBranchPoint(
        _ point: CGPoint,
        size: CGSize,
        solarState: SunGoldPhysics.SolarState,
        gust: CGFloat,
        branchSway: CGFloat
    ) -> CGPoint {
        let exposure = 1 - min(max(point.y, 0), 1)
        return CGPoint(
            x: size.width * (
                point.x + solarState.shadowDirection * 0.046
                    + gust * (0.004 + exposure * 0.010) + branchSway * exposure * 0.006
            ),
            y: size.height * (point.y + gust * exposure * 0.002)
        )
    }

    private func normalizedNoise(at position: Double, seed: UInt64) -> Double {
        (CoherentNoise.value(at: position, seed: seed) + 1) / 2
    }
}

private extension SunGoldTreeShadowModel {
    struct BranchSegment: Sendable {
        let start: CGPoint
        let end: CGPoint
        let thickness: CGFloat
        let opacity: Double
    }

    static let branches: [BranchSegment] = [
        BranchSegment(start: CGPoint(x: -0.08, y: 0.62), end: CGPoint(x: 0.16, y: 0.48), thickness: 0.014, opacity: 0.23),
        BranchSegment(start: CGPoint(x: 0.16, y: 0.48), end: CGPoint(x: 0.36, y: 0.33), thickness: 0.011, opacity: 0.22),
        BranchSegment(start: CGPoint(x: 0.36, y: 0.33), end: CGPoint(x: 0.58, y: 0.16), thickness: 0.008, opacity: 0.20),
        BranchSegment(start: CGPoint(x: 0.36, y: 0.33), end: CGPoint(x: 0.65, y: 0.39), thickness: 0.007, opacity: 0.18),
        BranchSegment(start: CGPoint(x: 0.16, y: 0.48), end: CGPoint(x: 0.40, y: 0.59), thickness: 0.007, opacity: 0.18),
        BranchSegment(start: CGPoint(x: 0.58, y: 0.16), end: CGPoint(x: 0.77, y: 0.08), thickness: 0.005, opacity: 0.17),
        BranchSegment(start: CGPoint(x: 0.58, y: 0.16), end: CGPoint(x: 0.76, y: 0.24), thickness: 0.005, opacity: 0.16),
        BranchSegment(start: CGPoint(x: 0.65, y: 0.39), end: CGPoint(x: 0.86, y: 0.31), thickness: 0.005, opacity: 0.16),
        BranchSegment(start: CGPoint(x: 0.65, y: 0.39), end: CGPoint(x: 0.82, y: 0.50), thickness: 0.004, opacity: 0.15),
        BranchSegment(start: CGPoint(x: 0.40, y: 0.59), end: CGPoint(x: 0.59, y: 0.70), thickness: 0.005, opacity: 0.16),
        BranchSegment(start: CGPoint(x: 1.08, y: 0.72), end: CGPoint(x: 0.84, y: 0.56), thickness: 0.012, opacity: 0.22),
        BranchSegment(start: CGPoint(x: 0.84, y: 0.56), end: CGPoint(x: 0.66, y: 0.43), thickness: 0.008, opacity: 0.19),
        BranchSegment(start: CGPoint(x: 0.84, y: 0.56), end: CGPoint(x: 0.68, y: 0.69), thickness: 0.006, opacity: 0.17),
        BranchSegment(start: CGPoint(x: 0.68, y: 0.69), end: CGPoint(x: 0.48, y: 0.81), thickness: 0.004, opacity: 0.15),
        BranchSegment(start: CGPoint(x: 0.68, y: 0.69), end: CGPoint(x: 0.84, y: 0.84), thickness: 0.004, opacity: 0.14),
        BranchSegment(start: CGPoint(x: -0.06, y: 0.20), end: CGPoint(x: 0.20, y: 0.25), thickness: 0.008, opacity: 0.19),
        BranchSegment(start: CGPoint(x: 0.20, y: 0.25), end: CGPoint(x: 0.40, y: 0.15), thickness: 0.005, opacity: 0.16),
        BranchSegment(start: CGPoint(x: 0.20, y: 0.25), end: CGPoint(x: 0.38, y: 0.38), thickness: 0.004, opacity: 0.15)
    ]

    static let foliageAnchors: [CGPoint] = [
        CGPoint(x: 0.02, y: 0.10), CGPoint(x: 0.18, y: 0.14),
        CGPoint(x: 0.34, y: 0.09), CGPoint(x: 0.52, y: 0.15),
        CGPoint(x: 0.70, y: 0.10), CGPoint(x: 0.89, y: 0.16),
        CGPoint(x: 0.08, y: 0.31), CGPoint(x: 0.27, y: 0.29),
        CGPoint(x: 0.47, y: 0.34), CGPoint(x: 0.68, y: 0.29),
        CGPoint(x: 0.88, y: 0.35), CGPoint(x: 0.15, y: 0.51),
        CGPoint(x: 0.36, y: 0.49), CGPoint(x: 0.58, y: 0.52),
        CGPoint(x: 0.80, y: 0.50), CGPoint(x: 0.94, y: 0.60),
        CGPoint(x: 0.24, y: 0.70), CGPoint(x: 0.48, y: 0.72),
        CGPoint(x: 0.72, y: 0.73), CGPoint(x: 0.88, y: 0.84)
    ]

    static let lobesPerCluster = 8
    static let lightFleckCount = 32
}
