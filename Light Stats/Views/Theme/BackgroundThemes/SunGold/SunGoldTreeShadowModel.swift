//
//  SunGoldTreeShadowModel.swift
//  Light Stats
//

import CoreGraphics
import Foundation

struct SunGoldTreeShadowModel: BackgroundOcclusionModel {
    let palette: SunGoldBackgroundTheme.Palette

    func makeOcclusions(
        time: TimeInterval,
        size: CGSize,
        configuration _: BackgroundSceneConfiguration
    ) -> [BackgroundSceneFrame.Primitive] {
        let solarState = SunGoldPhysics.solarState(time: time, size: size)
        let gust = SunGoldPhysics.gust(at: time)
        return branchShadows(time: time, size: size, solarState: solarState, gust: gust)
            + leafShadows(time: time, size: size, solarState: solarState, gust: gust)
    }

    private func branchShadows(
        time: TimeInterval,
        size: CGSize,
        solarState: SunGoldPhysics.SolarState,
        gust: CGFloat
    ) -> [BackgroundSceneFrame.Primitive] {
        let diagonal = hypot(size.width, size.height)
        return Self.branches.map { branch in
            let localSway = sin(CGFloat(time) * branch.frequency + branch.phase) * 0.45
            let sway = (gust * 0.55 + localSway) * 0.045
            let solarShift = solarState.shadowDirection * 0.055
            let mask = BackgroundSceneFrame.SoftMask(
                center: CGPoint(
                    x: size.width * (branch.position + sway + solarShift),
                    y: size.height * (0.51 + sway * 0.30)
                ),
                size: CGSize(width: max(22, size.width * branch.width), height: diagonal * 1.45),
                angle: branch.angle + sway * 1.7 + solarState.shadowDirection * 0.13,
                shape: .capsule,
                color: palette.treeShadow,
                opacity: branch.opacity,
                softness: min(size.width, size.height) * branch.softness,
                blendMode: .multiply
            )
            return .softMask(mask)
        }
    }

    private func leafShadows(
        time: TimeInterval,
        size: CGSize,
        solarState: SunGoldPhysics.SolarState,
        gust: CGFloat
    ) -> [BackgroundSceneFrame.Primitive] {
        Self.leaves.map { leaf in
            let flutter = sin(CGFloat(time) * leaf.frequency + leaf.phase)
            let sway = gust * 0.024 + flutter * 0.029
            let center = CGPoint(
                x: size.width * (
                    leaf.positionX + sway + solarState.shadowDirection * 0.046
                ),
                y: size.height * (leaf.positionY + cos(flutter + leaf.phase) * 0.009)
            )
            let mask = BackgroundSceneFrame.SoftMask(
                center: center,
                size: CGSize(width: size.width * leaf.width, height: size.height * leaf.height),
                angle: leaf.angle + flutter * 0.16 + solarState.shadowDirection * 0.08,
                shape: .ellipse,
                color: palette.treeShadow,
                opacity: leaf.opacity,
                softness: min(size.width, size.height) * leaf.softness,
                blendMode: .multiply
            )
            return .softMask(mask)
        }
    }
}

private extension SunGoldTreeShadowModel {
    struct BranchShadow: Sendable {
        let position: CGFloat
        let width: CGFloat
        let angle: CGFloat
        let phase: CGFloat
        let frequency: CGFloat
        let opacity: Double
        let softness: CGFloat
    }

    struct LeafShadow: Sendable {
        let positionX: CGFloat
        let positionY: CGFloat
        let width: CGFloat
        let height: CGFloat
        let angle: CGFloat
        let phase: CGFloat
        let frequency: CGFloat
        let opacity: Double
        let softness: CGFloat
    }

    static let branches: [BranchShadow] = [
        BranchShadow(
            position: 0.08, width: 0.13, angle: -0.32,
            phase: 0.2, frequency: 0.31, opacity: 0.32, softness: 0.046
        ),
        BranchShadow(
            position: 0.50, width: 0.09, angle: -0.24,
            phase: 2.1, frequency: 0.38, opacity: 0.26, softness: 0.040
        ),
        BranchShadow(
            position: 0.92, width: 0.16, angle: -0.37,
            phase: 4.3, frequency: 0.27, opacity: 0.34, softness: 0.052
        )
    ]

    static let leaves: [LeafShadow] = [
        LeafShadow(
            positionX: 0.08, positionY: 0.16, width: 0.28, height: 0.12, angle: -0.28,
            phase: 0.3, frequency: 0.72, opacity: 0.26, softness: 0.040
        ),
        LeafShadow(
            positionX: 0.31, positionY: 0.30, width: 0.20, height: 0.10, angle: 0.18,
            phase: 1.2, frequency: 0.88, opacity: 0.22, softness: 0.035
        ),
        LeafShadow(
            positionX: 0.72, positionY: 0.20, width: 0.26, height: 0.13, angle: -0.12,
            phase: 2.0, frequency: 0.64, opacity: 0.25, softness: 0.043
        ),
        LeafShadow(
            positionX: 0.94, positionY: 0.38, width: 0.22, height: 0.09, angle: 0.24,
            phase: 2.8, frequency: 0.91, opacity: 0.21, softness: 0.033
        ),
        LeafShadow(
            positionX: 0.18, positionY: 0.58, width: 0.24, height: 0.12, angle: -0.20,
            phase: 3.6, frequency: 0.78, opacity: 0.24, softness: 0.038
        ),
        LeafShadow(
            positionX: 0.58, positionY: 0.66, width: 0.30, height: 0.14, angle: 0.10,
            phase: 4.4, frequency: 0.68, opacity: 0.27, softness: 0.044
        ),
        LeafShadow(
            positionX: 0.86, positionY: 0.82, width: 0.25, height: 0.11, angle: -0.16,
            phase: 5.2, frequency: 0.84, opacity: 0.23, softness: 0.037
        )
    ]
}
