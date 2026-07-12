//
//  ThemePickerView.swift
//  Light Stats
//
//  Visual theme selector for Settings › General › Theme.
//

import SwiftUI

struct ThemePickerView: View {
    @Binding var selection: AppTheme
    @Environment(\.theme) private var activeTheme

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(AppTheme.allCases) { theme in
                themeTile(theme)
            }
        }
    }

    private func themeTile(_ theme: AppTheme) -> some View {
        let tokens = ThemeTokens.tokens(for: theme)
        let isSelected = selection == theme
        return Button {
            selection = theme
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Mini canvas preview
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tokens.usesMesh ? tokens.meshBase : tokens.canvas)
                    if tokens.usesMesh {
                        Circle()
                            .fill(tokens.meshBlobPrimary.opacity(0.9))
                            .frame(width: 48, height: 48)
                            .blur(radius: 10)
                            .offset(x: -14, y: -6)
                        Circle()
                            .fill(tokens.meshBlobSecondary.opacity(0.85))
                            .frame(width: 40, height: 40)
                            .blur(radius: 8)
                            .offset(x: 16, y: 10)
                    }
                    // Mini chrome: bento = 2×2 tiles; instrument = two flat chips.
                    if theme.usesBentoLayout {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 3),
                            GridItem(.flexible(), spacing: 3)
                        ], spacing: 3) {
                            ForEach(0..<4, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(tokens.surfaceFill)
                                    .frame(height: 14)
                                    .overlay(alignment: .bottomLeading) {
                                        Capsule()
                                            .fill(index % 2 == 0 ? tokens.signalGood : tokens.signalWarn)
                                            .frame(width: 8, height: 2)
                                            .padding(3)
                                    }
                            }
                        }
                        .padding(.horizontal, 10)
                    } else {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tokens.cardFill)
                                .frame(width: 28, height: 18)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tokens.cardFill)
                                .frame(width: 28, height: 18)
                        }
                        .overlay(
                            HStack(spacing: 4) {
                                Capsule().fill(tokens.signalGood).frame(width: 10, height: 3)
                                Capsule().fill(tokens.signalWarn).frame(width: 10, height: 3)
                            }
                            .offset(y: 4)
                        )
                    }
                }
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isSelected ? activeTheme.accent : tokens.surfaceStroke,
                            lineWidth: isSelected ? 2 : 0.5
                        )
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.titleKey.localized)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(activeTheme.inkPrimary)
                    Text(theme.subtitleKey.localized)
                        .font(.system(size: 10))
                        .foregroundStyle(activeTheme.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? activeTheme.accent.opacity(0.12) : activeTheme.surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? activeTheme.accent.opacity(0.5) : activeTheme.surfaceStroke,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
