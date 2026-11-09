//
//  AppSwitcherPanelMaterial.swift
//  Light Stats
//

import SwiftUI

/// The switcher panel's own material, shared by both presentation modes.
///
/// The switcher replaces a system control, so it gets the system's material: on macOS 26 that is
/// Liquid Glass, which is the only way to get that refraction — a material view plus a tint cannot
/// imitate it. Below 26 it falls back to the HUD material with a *light* tint: the panel used to sit
/// under `black.opacity(0.70)`, which covered the material completely and made the whole thing read
/// as a black box.
struct AppSwitcherPanelMaterial: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.45), lineWidth: 0.5)
                )
        }
    }
}
