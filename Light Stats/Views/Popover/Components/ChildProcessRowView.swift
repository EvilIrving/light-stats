//
//  ChildProcessRowView.swift
//  Light Stats
//
//  Child-process line under an expanded app row (display only).
//

import SwiftUI

/// 子进程列表项组件（仅显示，不可终止）
struct ChildProcessRowView: View {
    @Environment(\.theme) private var theme

    let command: String
    let memoryBytes: UInt64
    let indentation: CGFloat
    /// Instrument readout: tighter type, fainter ink.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Color.clear.frame(width: indentation)

            Text(command)
                .font(
                    compact
                        ? theme.chromeStyle.compactValueFont
                        : .system(size: 12)
                )
                .foregroundStyle(compact ? theme.inkFaint : theme.inkSecondary)
                .lineLimit(1)
                .help(command)

            Spacer(minLength: 6)

            Text(memoryFormatted)
                .font(
                    compact
                        ? theme.chromeStyle.compactLabelFont
                        : .system(size: 11, design: .monospaced)
                )
                .foregroundStyle(theme.inkFaint)
        }
        .padding(.leading, compact ? 0 : 8)
        .padding(.trailing, compact ? 4 : 0)
        .padding(.vertical, compact ? 4 : 6)
    }

    private var memoryFormatted: String {
        ByteFormatter.format(memoryBytes)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 4) {
        ChildProcessRowView(
            command: "claude",
            memoryBytes: 256 * 1024 * 1024,
            indentation: 24
        )
        ChildProcessRowView(
            command: "node",
            memoryBytes: 512 * 1024 * 1024,
            indentation: 8,
            compact: true
        )
    }
    .padding()
    .appThemed(AppTheme.film)
}
#endif
