//
//  PresentationCursorStylePicker.swift
//  Light Stats
//
//  Presentation-pointer colourway picker: the five pack colourways as thumbnails, so the
//  choice is made by looking at the cursor rather than reading its name. Names survive only
//  as the tooltip and accessibility label.
//

import AppKit
import SwiftUI

struct PresentationCursorStylePicker: View {
    @Binding var selection: PresentationCursorStyle

    /// Thumbnail box: the preview crop is 96×128, so 24×32pt keeps the arrow at the same
    /// scale in every option and stays pixel-exact on a 2× display.
    private static let thumbnailSize = CGSize(width: 24, height: 32)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PresentationCursorStyle.allCases) { style in
                option(style)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func option(_ style: PresentationCursorStyle) -> some View {
        let isSelected = selection == style
        let name = style.titleKey.localized
        return Button {
            selection = style
        } label: {
            Group {
                if let preview = PresentationCursorPreviewCache.image(for: style) {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.06 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Decodes each colourway's thumbnail once per process. The settings row is rebuilt on
/// every change to the page, and re-decoding five 768×1024 atlases there would be wasted
/// work; five 96×128 stills are ~320 KB in total.
@MainActor
private enum PresentationCursorPreviewCache {
    private static var images: [PresentationCursorStyle: NSImage] = [:]

    static func image(for style: PresentationCursorStyle) -> NSImage? {
        if let cached = images[style] { return cached }
        guard let image = PresentationCursorAtlas.previewImage(for: style) else { return nil }
        images[style] = image
        return image
    }
}
