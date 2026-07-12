//
//  ChildProcessRowView.swift
//  Light Stats
//
//  Created on 2026/02/04.
//

import SwiftUI

/// 子进程列表项组件（仅显示，不可终止）
struct ChildProcessRowView: View {
    @Environment(\.theme) private var theme

    let command: String
    let memoryBytes: UInt64
    let indentation: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: indentation)

            Text(command)
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary)
                .lineLimit(1)
                .help(command)

            Spacer()

            Text(memoryFormatted)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.inkFaint)
        }
        .padding(.leading, 8)
        .padding(.vertical, 6)
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
            indentation: 24
        )
    }
    .padding()
    .appThemed(.film)
}
#endif
