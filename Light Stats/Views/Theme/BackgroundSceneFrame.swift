//
//  BackgroundSceneFrame.swift
//  Light Stats
//

import CoreGraphics

/// Immutable, renderer-neutral output produced by a background scene model.
struct BackgroundSceneFrame: Equatable, Sendable {
    let primitives: [Primitive]

    func appending(_ additionalPrimitives: [Primitive]) -> BackgroundSceneFrame {
        BackgroundSceneFrame(primitives: primitives + additionalPrimitives)
    }

    enum Primitive: Equatable, Sendable {
        case colorFill(Color)
        case radialLight(RadialLight)
        case directionalLight(DirectionalLight)
        case projectedLight(ProjectedLight)
        case softMask(SoftMask)
        case readabilityRegion(ReadabilityRegion)
    }

    struct Color: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double

        init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.opacity = opacity
        }
    }

    struct RadialLight: Equatable, Sendable {
        let center: CGPoint
        let radius: CGFloat
        let innerColor: Color
        let outerColor: Color
        let intensity: Double
        let softness: CGFloat
        let blendMode: BlendMode
    }

    struct DirectionalLight: Equatable, Sendable {
        let center: CGPoint
        let length: CGFloat
        let width: CGFloat
        let angle: CGFloat
        let color: Color
        let intensity: Double
        let softness: CGFloat
        let blendMode: BlendMode
    }

    struct ProjectedLight: Equatable, Sendable {
        let source: CGPoint
        let target: CGPoint
        let sourceWidth: CGFloat
        let targetWidth: CGFloat
        let color: Color
        let intensity: Double
        let softness: CGFloat
        let blendMode: BlendMode
    }

    struct SoftMask: Equatable, Sendable {
        let center: CGPoint
        let size: CGSize
        let angle: CGFloat
        let shape: SoftMaskShape
        let color: Color
        let opacity: Double
        let softness: CGFloat
        let blendMode: BlendMode
        let role: SoftMaskRole
        let bodyOpacity: Double

        init(
            center: CGPoint,
            size: CGSize,
            angle: CGFloat,
            shape: SoftMaskShape,
            color: Color,
            opacity: Double,
            softness: CGFloat,
            blendMode: BlendMode,
            role: SoftMaskRole = .surfaceShadow,
            bodyOpacity: Double = 0
        ) {
            self.center = center
            self.size = size
            self.angle = angle
            self.shape = shape
            self.color = color
            self.opacity = opacity
            self.softness = softness
            self.blendMode = blendMode
            self.role = role
            self.bodyOpacity = bodyOpacity
        }
    }

    struct ReadabilityRegion: Equatable, Sendable {
        let bounds: CGRect
        let cornerRadius: CGFloat
        let color: Color
        let opacity: Double
        let softness: CGFloat
    }

    enum SoftMaskShape: Equatable, Sendable {
        case ellipse
        case capsule
    }

    enum SoftMaskRole: Equatable, Sendable {
        case surfaceShadow
        case lightOccluder
    }

    enum BlendMode: Equatable, Sendable {
        case normal
        case screen
        case plusLighter
        case multiply
    }
}
