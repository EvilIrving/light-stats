//
//  GapSlider.swift
//  Light Stats
//

import SwiftUI

/// A labelled gap slider that only reports its value when the gesture ends.
///
/// SwiftUI's `Slider` writes continuously, which is right for a value that is cheap to apply and
/// wrong here: each write persists the whole window-snap configuration and logs a settings change.
/// Dragging across the range would do that dozens of times a second while the user is still
/// choosing a number.
struct GapSlider: View {

    @Environment(\.theme) private var theme
    let title: String
    let value: CGFloat
    let onCommit: (CGFloat) -> Void

    @State private var draft: CGFloat?

    var body: some View {
        let current = draft ?? value
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.inkPrimary)
                Spacer()
                Text(String(format: "%.0f pt", current))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.inkSecondary)
            }
            Slider(
                value: Binding(
                    get: { current },
                    set: { draft = $0 }
                ),
                in: 0...SnapMargins.maximumGap,
                step: 2
            ) { editing in
                guard !editing, let committed = draft else { return }
                draft = nil
                onCommit(committed)
            }
            .controlSize(.small)
            .focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
