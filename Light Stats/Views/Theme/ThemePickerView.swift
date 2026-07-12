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
        let isSelected = selection == theme
        return Button {
            selection = theme
        } label: {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? activeTheme.accent.opacity(0.12) : activeTheme.surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? activeTheme.accent.opacity(0.5) : activeTheme.surfaceStroke,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
