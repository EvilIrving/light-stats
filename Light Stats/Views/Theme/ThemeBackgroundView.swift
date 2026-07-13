//
//  ThemeBackgroundView.swift
//  Light Stats
//

import SwiftUI

/// Selects a registered scene without knowing any concrete background theme.
struct ThemeBackgroundView: View {
    let tokens: ThemeTokens
    let appearance: ThemeAppearanceConfiguration
    var cornerRadius: CGFloat = 12
    var configuresWindow: Bool = false
    var fallbackMaterial: NSVisualEffectView.Material = .sidebar

    init(
        tokens: ThemeTokens,
        appearance: ThemeAppearanceConfiguration? = nil,
        cornerRadius: CGFloat = 12,
        configuresWindow: Bool = false,
        fallbackMaterial: NSVisualEffectView.Material = .sidebar
    ) {
        self.tokens = tokens
        self.appearance = appearance ?? .defaults(for: tokens.theme)
        self.cornerRadius = cornerRadius
        self.configuresWindow = configuresWindow
        self.fallbackMaterial = fallbackMaterial
    }

    var body: some View {
        Group {
            if let definition = BackgroundThemeRegistry.definition(for: tokens.theme) {
                RegisteredBackgroundScene(
                    definition: definition,
                    appearance: appearance
                )
                .id(definition.identifier)
            } else if tokens.usesGlass {
                GlassBackgroundView(
                    cornerRadius: cornerRadius,
                    fallbackMaterial: fallbackMaterial,
                    configuresWindow: configuresWindow
                )
            } else {
                tokens.canvas
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct RegisteredBackgroundScene: View {
    let definition: BackgroundThemeDefinition
    let appearance: ThemeAppearanceConfiguration

    @StateObject private var clock: BackgroundMotionClock

    init(
        definition: BackgroundThemeDefinition,
        appearance: ThemeAppearanceConfiguration
    ) {
        self.definition = definition
        self.appearance = appearance
        _clock = StateObject(
            wrappedValue: BackgroundMotionClock(intensity: appearance.dynamics)
        )
    }

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 24.0, paused: clock.isPaused)
        ) { context in
            GeometryReader { geometry in
                scene(at: context.date, size: geometry.size)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: appearance.dynamics) { _, dynamics in
            clock.setIntensity(dynamics)
        }
    }

    private func scene(at date: Date, size: CGSize) -> some View {
        let sample = clock.sample(at: date)
        let configuration = BackgroundSceneConfiguration(intensity: sample.intensity)
        let frame = definition.makeFrame(
            time: sample.time,
            size: size,
            configuration: configuration
        )
        return ZStack {
            BackgroundRenderer(frame: frame)
            BackgroundMaterialOverlay(
                effects: definition.materialEffects,
                configuration: BackgroundMaterialConfiguration(
                    grainEnabled: appearance.grainEnabled
                )
            )
        }
        .frame(width: size.width, height: size.height)
    }
}
