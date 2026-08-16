//
//  AppRowView.swift
//  Light Stats
//
//  Running-app row for Cleanup. Bento keeps card chips; instrument themes
//  (film / glass / noir) use a soft readout list aligned with Overview MetricRow.
//

import SwiftUI

struct AppCardView: View {
    /// 展开按钮列宽度，无子进程时用等宽占位保持对齐
    private static let expandColumnWidth: CGFloat = 10

    let app: RunningApp
    var isTerminating: Bool = false
    let appManager: AppMemoryManager
    let onClose: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var cachedChildProcesses: [TopProcessInfo] = []

    private var usesBento: Bool { theme.usesBentoLayout }

    private var iconSize: CGFloat { usesBento ? 28 : 22 }
    private var rowHSpacing: CGFloat { usesBento ? 12 : 10 }
    private var clusterSpacing: CGFloat { usesBento ? 6 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if isExpanded {
                childProcessList
            }
        }
        .onAppear {
            updateChildProcesses()
        }
        .onChange(of: app.allPids) { _, _ in
            updateChildProcesses()
        }
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(spacing: rowHSpacing) {
            expandCluster

            Text(app.displayName)
                .font(.system(size: usesBento ? 13 : 12, weight: .medium))
                .foregroundStyle(theme.inkPrimary)
                .lineLimit(1)
                .opacity(isTerminating ? 0.5 : 1.0)

            Spacer(minLength: 8)

            Text(app.memoryFormatted)
                .font(.system(size: usesBento ? 12 : 11, design: .monospaced))
                .foregroundStyle(theme.inkSecondary)
                .opacity(isTerminating ? 0.5 : 1.0)

            trailingControl
        }
        .padding(.horizontal, usesBento ? 8 : 6)
        .padding(.vertical, usesBento ? 9 : 6)
        .background(rowHoverBackground)
        .contentShape(RoundedRectangle(cornerRadius: usesBento ? 6 : 8, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .allowsHitTesting(!isTerminating)
    }

    private var expandCluster: some View {
        HStack(spacing: clusterSpacing) {
            Group {
                if !childProcesses.isEmpty {
                    expandButton
                } else {
                    Color.clear
                        .frame(width: Self.expandColumnWidth, height: Self.expandColumnWidth)
                }
            }
            .frame(width: Self.expandColumnWidth, height: Self.expandColumnWidth)

            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .opacity(isTerminating ? 0.5 : 1.0)
        }
        .padding(.vertical, usesBento ? 6 : 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !childProcesses.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isTerminating {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        } else if app.isTerminable {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: usesBento ? 16 : 14))
                    .foregroundStyle(isHovered ? theme.signalBad.opacity(0.9) : theme.inkFaint)
                    .padding(usesBento ? 4 : 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minWidth: usesBento ? 24 : 20, minHeight: usesBento ? 24 : 20)
            .allowsHitTesting(true)
            .help("关闭应用")
        }
    }

    @ViewBuilder
    private var rowHoverBackground: some View {
        if usesBento {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? theme.rowHoverFill : Color.clear)
        } else {
            // Soft instrument wash — continuous radius, inset so it never reads as a hard bar.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? theme.rowHoverFill.opacity(0.40) : Color.clear)
        }
    }

    private var expandButton: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.inkSecondary)
            .frame(width: Self.expandColumnWidth, height: Self.expandColumnWidth)
    }

    // MARK: - Children

    @ViewBuilder
    private var childProcessList: some View {
        if usesBento {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(childProcesses, id: \.pid) { process in
                    ChildProcessRowView(
                        command: process.command,
                        memoryBytes: process.memoryBytes,
                        indentation: 12
                    )
                    if process.pid != childProcesses.last?.pid {
                        Divider()
                            .padding(.leading, 48)
                            .opacity(0.5)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
        } else {
            HStack(alignment: .top, spacing: 0) {
                // Rail under the icon cluster — film instrument tree cue.
                Rectangle()
                    .fill(theme.lineHairline)
                    .frame(width: 1)
                    .padding(.leading, Self.expandColumnWidth + clusterSpacing + iconSize / 2)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(childProcesses, id: \.pid) { process in
                        ChildProcessRowView(
                            command: process.command,
                            memoryBytes: process.memoryBytes,
                            indentation: 8,
                            compact: true
                        )
                        if process.pid != childProcesses.last?.pid {
                            Rectangle()
                                .fill(theme.lineHairline.opacity(0.7))
                                .frame(height: 1)
                                .padding(.leading, 8)
                        }
                    }
                }
                .padding(.leading, 6)
            }
            .padding(.top, 2)
            .padding(.bottom, 6)
            .padding(.trailing, 6)
        }
    }

    // MARK: - Helpers

    private var childProcesses: [TopProcessInfo] {
        cachedChildProcesses
    }

    private func updateChildProcesses() {
        cachedChildProcesses = appManager.childProcesses(for: app)
    }
}

#if DEBUG
#Preview("Film") {
    previewStack.appThemed(AppTheme.film)
}

#Preview("Bento") {
    previewStack.appThemed(AppTheme.bento)
}

private var previewStack: some View {
    let icon = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) ?? NSImage()
    let mockApp = AppGroup(
        id: 1234,
        name: "iTerm2",
        icon: icon,
        totalMemoryBytes: 1024 * 1024 * 100,
        processCount: 4,
        allPids: [1234, 5678, 9012, 3456],
        terminablePids: [1234, 5678, 9012, 3456],
        isTerminable: true,
        bundleIdentifier: "com.googlecode.iterm2",
        bundlePath: "/Applications/iTerm.app",
        execPath: "/Applications/iTerm.app/Contents/MacOS/iTerm2"
    )
    let singleApp = AppGroup(
        id: 9999,
        name: "Safari",
        icon: icon,
        totalMemoryBytes: 500 * 1024 * 1024,
        processCount: 1,
        allPids: [9999],
        terminablePids: [9999],
        isTerminable: true,
        bundleIdentifier: "com.apple.safari",
        bundlePath: "/Applications/Safari.app",
        execPath: "/Applications/Safari.app/Contents/MacOS/Safari"
    )
    return VStack(spacing: 0) {
        AppCardView(app: mockApp, isTerminating: false, appManager: AppMemoryManager.shared) {}
        AppCardView(app: singleApp, isTerminating: false, appManager: AppMemoryManager.shared) {}
    }
    .padding()
}
#endif
