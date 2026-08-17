//
//  TechnicalPaperScene.swift
//  Light Stats
//

import SwiftUI

struct TechnicalPaperScene: View {
    let configuration: TechnicalPaperSceneConfiguration
    @Environment(\.displayScale) private var displayScale

    init(configuration: TechnicalPaperSceneConfiguration = .defaults) {
        self.configuration = configuration
    }

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(configuration.baseColor)
            )
            drawGrid(in: &context, size: size)
            drawRegistrationMarks(in: &context, size: size)
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        if configuration.showsMinorGrid {
            context.stroke(
                gridPath(size: size, spacing: configuration.minorGridSpacing),
                with: .color(configuration.minorGridColor.opacity(configuration.minorGridOpacity)),
                lineWidth: configuration.minorLineWidth
            )
        }
        if configuration.showsMajorGrid {
            context.stroke(
                gridPath(size: size, spacing: configuration.majorGridSpacing),
                with: .color(configuration.majorGridColor.opacity(configuration.majorGridOpacity)),
                lineWidth: configuration.majorLineWidth
            )
        }
    }

    private func gridPath(size: CGSize, spacing: CGFloat) -> Path {
        guard spacing > 0 else { return Path() }
        var path = Path()
        var position = spacing
        while position < size.width {
            let x = pixelAligned(position)
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            position += spacing
        }
        position = spacing
        while position < size.height {
            let y = pixelAligned(position)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            position += spacing
        }
        return path
    }

    private func drawRegistrationMarks(in context: inout GraphicsContext, size: CGSize) {
        guard configuration.showsRegistrationMarks else { return }
        let inset = configuration.registrationInset
        guard size.width > inset * 2, size.height > inset * 2 else { return }
        let points = [
            CGPoint(x: inset, y: inset),
            CGPoint(x: size.width - inset, y: inset),
            CGPoint(x: inset, y: size.height - inset),
            CGPoint(x: size.width - inset, y: size.height - inset)
        ]
        var path = Path()
        for point in points {
            let length = configuration.registrationMarkLength
            path.move(to: CGPoint(x: point.x - length, y: point.y))
            path.addLine(to: CGPoint(x: point.x + length, y: point.y))
            path.move(to: CGPoint(x: point.x, y: point.y - length))
            path.addLine(to: CGPoint(x: point.x, y: point.y + length))
        }
        context.stroke(
            path,
            with: .color(configuration.registrationColor.opacity(configuration.registrationOpacity)),
            lineWidth: configuration.registrationLineWidth
        )
    }

    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded() / scale
    }
}
