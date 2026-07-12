//
//  ThemePickerView.swift
//  Light Stats
//
//  Theme selector for Settings › General › Theme.
//  Same one-line segmented control pattern as language / log level.
//

import SwiftUI

struct ThemePickerView: View {
    @Binding var selection: AppTheme

    var body: some View {
        // Order = AppTheme.allCases: Default → Bento → Sun Gold → Ink Night.
        // Slightly wider segments than language (4 labels, some multi-word).
        SettingsSegmentedPicker(selection: $selection, segmentMinWidth: 56) {
            ForEach(AppTheme.allCases) { theme in
                SettingsSegmentLabel(title: theme.titleKey.localized).tag(theme)
            }
        }
    }
}
