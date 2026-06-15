//
//  ChildProcessRowView.swift
//  Light Stats
//
//  Created on 2026/02/04.
//

import SwiftUI

/// 子进程列表项组件（仅显示，不可终止）
struct ChildProcessRowView: View {
    let command: String
    let memoryBytes: UInt64
    let indentation: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            // 缩进占位
            Color.clear.frame(width: indentation)

            // 子进程名称
            Text(command)
                .font(.system(size: 12))
                .foregroundColor(.labelMuted)
                .lineLimit(1)
                .help(command)

            Spacer()

            // 内存
            Text(memoryFormatted)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.8))
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
}
#endif
