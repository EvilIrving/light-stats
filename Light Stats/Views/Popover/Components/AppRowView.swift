//
//  AppRowView.swift
//  Light Stats
//
//  Running-app row for Cleanup. Instrument row geometry shared by all themes;
//  ThemeChromeStyle controls the visual treatment.
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

    private var iconSize: CGFloat { 22 }
    private var rowHSpacing: CGFloat { 10 }
    private var clusterSpacing: CGFloat { 5 }

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
                .font(theme.chromeStyle.compactValueFont)
                .foregroundStyle(theme.inkPrimary)
                .lineLimit(1)
                .opacity(isTerminating ? 0.5 : 1.0)

            Spacer(minLength: 8)

            Text(app.memoryFormatted)
                .font(theme.chromeStyle.compactValueFont)
                .foregroundStyle(theme.inkSecondary)
                .opacity(isTerminating ? 0.5 : 1.0)

            trailingControl
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(rowHoverBackground)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .padding(.vertical, 2)
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
                    .font(.system(size: 14))
                    .foregroundStyle(isHovered ? theme.signalBad.opacity(0.9) : theme.inkFaint)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minWidth: 20, minHeight: 20)
            .allowsHitTesting(true)
            .help("关闭应用")
        }
    }

    @ViewBuilder
    private var rowHoverBackground: some View {
        if theme.chromeStyle.usesNightBarTreatment {
            RoundedRectangle(
                cornerRadius: theme.chromeStyle.surfaceCornerRadius,
                style: .continuous
            )
            .fill(Color.clear)
            .overlay(alignment: .leading) {
                if isHovered {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [theme.signalAccent, theme.signalGood],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: 2)
                        .padding(.vertical, 6)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.lineHairline.opacity(isHovered ? 0.72 : 0.36))
                    .frame(height: 0.5)
                    .padding(.leading, 42)
            }
        } else if theme.chromeStyle.usesNeonTreatment {
            RoundedRectangle(
                cornerRadius: theme.chromeStyle.surfaceCornerRadius,
                style: .continuous
            )
            .fill(isHovered ? theme.rowHoverFill : theme.surfaceFill.opacity(0.50))
            .overlay(
                RoundedRectangle(
                    cornerRadius: theme.chromeStyle.surfaceCornerRadius,
                    style: .continuous
                )
                .stroke(
                    isHovered ? theme.signalInfo.opacity(0.48) : theme.surfaceStroke.opacity(0.24),
                    lineWidth: theme.chromeStyle.surfaceStrokeWidth
                )
            )
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
