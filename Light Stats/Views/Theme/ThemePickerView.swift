//
//  ThemePickerView.swift
//  Light Stats
//
//  Theme selector for Settings › General › Theme. Uses a dedicated compact
//  control instead of AppKit segmented Picker, which forces equal segment
//  widths and truncates labels when the live preview shares the row.
//

import SwiftUI

struct ThemePickerView: View {
    @Binding var selection: AppTheme

    var body: some View {
        // Order = AppTheme.visibleCases: Default → Orange Sea → Night Bar → Ink Night.
        // Data Paper is temporarily hidden (isVisible = false) — not deleted.
        HStack(spacing: 1) {
            ForEach(AppTheme.visibleCases) { theme in
                option(theme)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .focusable(false)
    }

    private func option(_ theme: AppTheme) -> some View {
        let isSelected = selection == theme
        return Button {
            selection = theme
        } label: {
            Text(theme.titleKey.localized)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.82))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .frame(minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
