//
//  ProcessDetailRowView.swift
//  Light Stats
//
//  One line of an expanded app row (display only).
//

import SwiftUI

/// 应用展开后的成员行（仅显示，不可终止）
struct ProcessDetailRowView: View {
    @Environment(\.theme) private var theme

    let entry: ChildProcessDisplayPolicy.Entry
    let indentation: CGFloat
    /// Instrument readout: tighter type, fainter ink.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Color.clear.frame(width: indentation)

            Text(entry.label)
                .font(
                    compact
                        ? theme.chromeStyle.compactValueFont
                        : .system(size: 12)
                )
                .foregroundStyle(compact ? theme.inkFaint : theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(tooltip)

            if entry.showsPID {
                // `Text("#\(pid)")` is a localized key, which would group the digits.
                Text(verbatim: "#\(entry.pid)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.inkFaint.opacity(0.7))
                    .lineLimit(1)
            }

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

    private var tooltip: String {
        "#\(entry.pid)  \(entry.detail)"
    }

    private var memoryFormatted: String {
        guard let memoryBytes = entry.memoryBytes else { return "—" }
        return ByteFormatter.format(memoryBytes)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 4) {
        ProcessDetailRowView(
            entry: ChildProcessDisplayPolicy.Entry(
                pid: 4321,
                label: "Figma Helper (Renderer)",
                detail: "/Applications/Figma.app/Contents/Frameworks/Figma Helper (Renderer).app/Contents/MacOS/Figma Helper (Renderer)",
                memoryBytes: 512 * 1024 * 1024,
                showsPID: false
            ),
            indentation: 8,
            compact: true
        )
        ProcessDetailRowView(
            entry: ChildProcessDisplayPolicy.Entry(
                pid: 8765,
                label: "node",
                detail: "/Users/actor/.local/share/fnm/node-versions/v24.21.0/installation/bin/node",
                memoryBytes: 256 * 1024 * 1024,
                showsPID: true
            ),
            indentation: 8,
            compact: true
        )
        ProcessDetailRowView(
            entry: ChildProcessDisplayPolicy.Entry(
                pid: 1,
                label: "silora-helper",
                detail: "/Library/PrivilegedHelperTools/com.silora.mobileclient.mac.helper/silora-helper",
                memoryBytes: nil,
                showsPID: false
            ),
            indentation: 8,
            compact: true
        )
    }
    .padding()
    .appThemed(AppTheme.film)
}
#endif
