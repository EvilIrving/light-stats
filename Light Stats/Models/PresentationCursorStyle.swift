//
//  PresentationCursorStyle.swift
//  Light Stats
//
//  The five presentation-pointer colourways from the asset pack. Pure data:
//  which sprite atlas to draw and where the arrow tip sits inside a frame —
//  `动画参数.json` is the source for both.
//

import CoreGraphics

nonisolated enum PresentationCursorStyle: String, CaseIterable, Sendable, Identifiable {
    case holographicSilver
    case iceCrystal
    case rosePink
    case aurora
    case obsidian

    /// Shipped default: 全息银钻 — a light body with a dark keyline, so the pointer
    /// stays legible over light and dark content alike.
    static let shippedDefault: PresentationCursorStyle = .holographicSilver

    var id: String { rawValue }

    /// Settings label and the picker's tooltip / accessibility name.
    var titleKey: String { "settings.presentationCursor.style.\(rawValue)" }

    /// Bundle name of the 768×1024 sprite atlas (48 frames, 6×8 cells of 128px).
    /// Spelled out per case rather than derived from `rawValue`, because a name that
    /// stops matching the bundled file would only show up as a pointer that never starts.
    var atlasResourceName: String {
        switch self {
        case .holographicSilver: return "PresentationCursorHolographicSilver"
        case .iceCrystal: return "PresentationCursorIceCrystal"
        case .rosePink: return "PresentationCursorRosePink"
        case .aurora: return "PresentationCursorAurora"
        case .obsidian: return "PresentationCursorObsidian"
        }
    }

    /// Arrow tip inside one atlas cell, in cell pixels from the cell's top-left corner
    /// (the pack's `热点_128像素`). `PresentationCursorGeometry` scales it to the
    /// rendered size; a wrong value misplaces the click point, not just the art.
    var cellHotspot: CGPoint {
        switch self {
        case .holographicSilver: return CGPoint(x: 24.131, y: 4.109)
        case .iceCrystal: return CGPoint(x: 23.191, y: 4.0)
        case .rosePink: return CGPoint(x: 23.826, y: 4.0)
        case .aurora: return CGPoint(x: 21.224, y: 4.107)
        case .obsidian: return CGPoint(x: 20.893, y: 4.0)
        }
    }
}
