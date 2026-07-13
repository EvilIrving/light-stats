//
//  BackgroundRenderer.swift
//  Light Stats
//

import SwiftUI

/// Draws standard primitives and removes occluded energy inside each light layer.
struct BackgroundRenderer: View {
    let frame: BackgroundSceneFrame

    var body: some View {
        Canvas(opaque: true, colorMode: .extendedLinear, rendersAsynchronously: true) { context, size in
            drawColorFills(in: &context, canvasSize: size)
            let occluders = lightOccluders
            for primitive in frame.primitives {
                drawLight(primitive, occluders: occluders, in: &context)
            }
            drawSurfaceMasks(surfaceShadows, blendMode: .multiply, in: &context)
            drawSurfaceMasks(surfaceHighlights, blendMode: .plusLighter, in: &context)
            for primitive in frame.primitives {
                drawForeground(primitive, in: &context)
            }
        }
    }

    private var lightOccluders: [BackgroundSceneFrame.SoftMask] {
        frame.primitives.compactMap { primitive in
            guard case let .softMask(mask) = primitive, mask.role == .lightOccluder else {
                return nil
            }
            return mask
        }
    }

    private var surfaceShadows: [BackgroundSceneFrame.SoftMask] {
        frame.primitives.compactMap { primitive in
            guard case let .softMask(mask) = primitive, mask.role == .surfaceShadow else {
                return nil
            }
            return mask
        }
    }

    private var surfaceHighlights: [BackgroundSceneFrame.SoftMask] {
        frame.primitives.compactMap { primitive in
            guard case let .softMask(mask) = primitive, mask.role == .surfaceHighlight else {
                return nil
            }
            return mask
        }
    }

    private func drawColorFills(
        in context: inout GraphicsContext,
        canvasSize: CGSize
    ) {
        for primitive in frame.primitives {
            guard case let .colorFill(color) = primitive else { continue }
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(swiftUIColor(color))
            )
        }
    }

    private func drawLight(
        _ primitive: BackgroundSceneFrame.Primitive,
        occluders: [BackgroundSceneFrame.SoftMask],
        in context: inout GraphicsContext
    ) {
        guard let lightBlendMode = lightBlendMode(for: primitive) else { return }
        context.blendMode = lightBlendMode
        context.drawLayer { layer in
            switch primitive {
            case let .radialLight(light):
                drawRadialLight(light, in: &layer)
            case let .directionalLight(light):
                drawDirectionalLight(light, in: &layer)
            case let .projectedLight(light):
                drawProjectedLight(light, in: &layer)
            default:
                break
            }
            for occluder in occluders {
                drawLightOccluder(occluder, in: &layer)
            }
        }
        context.blendMode = .normal
    }

    private func drawForeground(
        _ primitive: BackgroundSceneFrame.Primitive,
        in context: inout GraphicsContext
    ) {
        switch primitive {
        case let .softMask(mask) where mask.role == .lightOccluder:
            drawVisibleMask(mask, in: &context)
        case let .readabilityRegion(region):
            drawReadabilityRegion(region, in: &context)
        default:
            break
        }
    }

    private func drawSurfaceMasks(
        _ masks: [BackgroundSceneFrame.SoftMask],
        blendMode: GraphicsContext.BlendMode,
        in context: inout GraphicsContext
    ) {
        guard !masks.isEmpty else { return }
        let softness = masks.map(\.softness).reduce(0, +) / CGFloat(masks.count)
        context.blendMode = blendMode
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: softness))
            for mask in masks {
                layer.fill(
                    maskPath(mask),
                    with: .color(swiftUIColor(mask.color).opacity(mask.opacity))
                )
            }
        }
        context.blendMode = .normal
    }

    private func drawRadialLight(
        _ light: BackgroundSceneFrame.RadialLight,
        in context: inout GraphicsContext
    ) {
        let bounds = CGRect(
            x: light.center.x - light.radius,
            y: light.center.y - light.radius,
            width: light.radius * 2,
            height: light.radius * 2
        )
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: light.softness))
            layer.fill(
                Path(ellipseIn: bounds),
                with: .radialGradient(
                    Gradient(colors: [
                        swiftUIColor(light.innerColor).opacity(light.intensity),
                        swiftUIColor(light.outerColor).opacity(light.intensity * 0.72),
                        swiftUIColor(light.outerColor).opacity(0)
                    ]),
                    center: light.center,
                    startRadius: 0,
                    endRadius: light.radius
                )
            )
        }
    }

    private func drawDirectionalLight(
        _ light: BackgroundSceneFrame.DirectionalLight,
        in context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: light.center.x - light.length / 2,
            y: light.center.y - light.width / 2,
            width: light.length,
            height: light.width
        )
        var path = Path(roundedRect: rect, cornerRadius: light.width / 2)
        let transform = CGAffineTransform(translationX: light.center.x, y: light.center.y)
            .rotated(by: light.angle)
            .translatedBy(x: -light.center.x, y: -light.center.y)
        path = path.applying(transform)
        let normal = CGVector(dx: -sin(light.angle), dy: cos(light.angle))
        drawSoftBeam(
            path: path,
            center: light.center,
            normal: normal,
            width: light.width,
            color: light.color,
            intensity: light.intensity,
            softness: light.softness,
            in: &context
        )
    }

    private func drawProjectedLight(
        _ light: BackgroundSceneFrame.ProjectedLight,
        in context: inout GraphicsContext
    ) {
        let outerPath = projectedPath(
            source: light.source,
            target: light.target,
            sourceWidth: light.sourceWidth,
            targetWidth: light.targetWidth
        )
        let innerPath = projectedPath(
            source: light.source,
            target: light.target,
            sourceWidth: light.sourceWidth * 0.42,
            targetWidth: light.targetWidth * 0.46
        )
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: light.softness))
            layer.fill(
                outerPath,
                with: .linearGradient(
                    Gradient(colors: [
                        swiftUIColor(light.color).opacity(light.intensity * 0.58),
                        swiftUIColor(light.color).opacity(light.intensity * 0.82),
                        swiftUIColor(light.color).opacity(light.intensity * 0.34)
                    ]),
                    startPoint: light.source,
                    endPoint: light.target
                )
            )
            layer.fill(
                innerPath,
                with: .linearGradient(
                    Gradient(colors: [
                        swiftUIColor(light.color).opacity(light.intensity * 0.34),
                        swiftUIColor(light.color).opacity(light.intensity * 0.54),
                        swiftUIColor(light.color).opacity(light.intensity * 0.18)
                    ]),
                    startPoint: light.source,
                    endPoint: light.target
                )
            )
        }
    }

    private func drawSoftBeam(
        path: Path,
        center: CGPoint,
        normal: CGVector,
        width: CGFloat,
        color: BackgroundSceneFrame.Color,
        intensity: Double,
        softness: CGFloat,
        in context: inout GraphicsContext
    ) {
        let halfWidth = width / 2
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: softness))
            layer.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        swiftUIColor(color).opacity(0),
                        swiftUIColor(color).opacity(intensity * 0.72),
                        swiftUIColor(color).opacity(intensity),
                        swiftUIColor(color).opacity(intensity * 0.72),
                        swiftUIColor(color).opacity(0)
                    ]),
                    startPoint: CGPoint(
                        x: center.x - normal.dx * halfWidth,
                        y: center.y - normal.dy * halfWidth
                    ),
                    endPoint: CGPoint(
                        x: center.x + normal.dx * halfWidth,
                        y: center.y + normal.dy * halfWidth
                    )
                )
            )
        }
    }

    private func drawLightOccluder(
        _ mask: BackgroundSceneFrame.SoftMask,
        in context: inout GraphicsContext
    ) {
        context.drawLayer { layer in
            layer.blendMode = .destinationOut
            layer.addFilter(.blur(radius: mask.softness))
            layer.fill(maskPath(mask), with: .color(.white.opacity(mask.opacity)))
        }
    }

    private func drawVisibleMask(
        _ mask: BackgroundSceneFrame.SoftMask,
        in context: inout GraphicsContext
    ) {
        let opacity = mask.role == .lightOccluder ? mask.bodyOpacity : mask.opacity
        guard opacity > 0 else { return }
        context.drawLayer { layer in
            layer.blendMode = mask.role == .lightOccluder ? .normal : blendMode(mask.blendMode)
            layer.addFilter(.blur(radius: mask.softness))
            layer.fill(maskPath(mask), with: .color(swiftUIColor(mask.color).opacity(opacity)))
        }
    }

    private func maskPath(_ mask: BackgroundSceneFrame.SoftMask) -> Path {
        let rect = CGRect(
            x: mask.center.x - mask.size.width / 2,
            y: mask.center.y - mask.size.height / 2,
            width: mask.size.width,
            height: mask.size.height
        )
        var path: Path
        switch mask.shape {
        case .ellipse:
            path = Path(ellipseIn: rect)
        case .leaf:
            path = leafPath(in: rect)
        case .capsule:
            path = Path(roundedRect: rect, cornerRadius: min(mask.size.width, mask.size.height) / 2)
        }
        let transform = CGAffineTransform(translationX: mask.center.x, y: mask.center.y)
            .rotated(by: mask.angle)
            .translatedBy(x: -mask.center.x, y: -mask.center.y)
        return path.applying(transform)
    }

    private func leafPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.maxY),
            control2: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY - rect.height * 0.06)
        )
        path.closeSubpath()
        return path
    }

    private func projectedPath(
        source: CGPoint,
        target: CGPoint,
        sourceWidth: CGFloat,
        targetWidth: CGFloat
    ) -> Path {
        let deltaX = target.x - source.x
        let deltaY = target.y - source.y
        let length = max(hypot(deltaX, deltaY), 1)
        let normal = CGVector(dx: -deltaY / length, dy: deltaX / length)
        var path = Path()
        path.move(to: CGPoint(
            x: source.x + normal.dx * sourceWidth / 2,
            y: source.y + normal.dy * sourceWidth / 2
        ))
        path.addLine(to: CGPoint(
            x: target.x + normal.dx * targetWidth / 2,
            y: target.y + normal.dy * targetWidth / 2
        ))
        path.addLine(to: CGPoint(
            x: target.x - normal.dx * targetWidth / 2,
            y: target.y - normal.dy * targetWidth / 2
        ))
        path.addLine(to: CGPoint(
            x: source.x - normal.dx * sourceWidth / 2,
            y: source.y - normal.dy * sourceWidth / 2
        ))
        path.closeSubpath()
        return path
    }

    private func drawReadabilityRegion(
        _ region: BackgroundSceneFrame.ReadabilityRegion,
        in context: inout GraphicsContext
    ) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: region.softness))
            let path = Path(roundedRect: region.bounds, cornerRadius: region.cornerRadius)
            layer.fill(path, with: .color(swiftUIColor(region.color).opacity(region.opacity)))
        }
    }

    private func lightBlendMode(
        for primitive: BackgroundSceneFrame.Primitive
    ) -> GraphicsContext.BlendMode? {
        switch primitive {
        case let .radialLight(light): return blendMode(light.blendMode)
        case let .directionalLight(light): return blendMode(light.blendMode)
        case let .projectedLight(light): return blendMode(light.blendMode)
        default: return nil
        }
    }

    private func swiftUIColor(_ color: BackgroundSceneFrame.Color) -> Color {
        Color(
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.opacity
        )
    }

    private func blendMode(_ blendMode: BackgroundSceneFrame.BlendMode) -> GraphicsContext.BlendMode {
        switch blendMode {
        case .normal: return .normal
        case .screen: return .screen
        case .plusLighter: return .plusLighter
        case .multiply: return .multiply
        }
    }
}
