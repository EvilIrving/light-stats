//
//  SnapLayoutPreview.swift
//  Light Stats
//

import SwiftUI

struct SnapLayoutPreview: View {
    let layout: SnapLayout
    var margins: SnapMargins = .zero
    var sourceSize: CGSize = SnapLayoutProjection.referenceSize
    var selectedID: String?
    var ink: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(layout.segments) { segment in
                    let frame = SnapLayoutProjection.frame(
                        for: segment.rect, in: CGRect(origin: .zero, size: proxy.size),
                        margins: margins, sourceSize: sourceSize
                    )
                    RoundedRectangle(cornerRadius: min(3, frame.height / 8))
                        .fill(ink.opacity(selectedID == segment.id ? 0.40 : 0.13))
                        .overlay {
                            RoundedRectangle(cornerRadius: min(3, frame.height / 8))
                                .strokeBorder(ink.opacity(0.6), lineWidth: 0.75)
                        }
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SnapIslandText.title(for: layout))
    }
}
