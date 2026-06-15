//
//  AppRowView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct AppCardView: View {
    /// 展开按钮列宽度，无子进程时用等宽占位保持对齐
    private static let expandColumnWidth: CGFloat = 10

    let app: RunningApp
    var isTerminating: Bool = false
    let appManager: AppMemoryManager
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var cachedChildProcesses: [TopProcessInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 主卡片行
            HStack(spacing: 12) {
                // 展开区域 + 图标（间距较小，减少展开按钮右侧留白）
                HStack(spacing: 6) {
                    Group {
                        if !childProcesses.isEmpty {
                            expandButton
                                .allowsHitTesting(true)
                        } else {
                            Color.clear
                                .frame(width: AppCardView.expandColumnWidth, height: AppCardView.expandColumnWidth)
                        }
                    }
                    .frame(width: AppCardView.expandColumnWidth, height: AppCardView.expandColumnWidth)

                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .opacity(isTerminating ? 0.5 : 1.0)
                }

                // App Name
                Text(app.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .opacity(isTerminating ? 0.5 : 1.0)

                Spacer()

                // Memory Usage
                Text(app.memoryFormatted)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.labelMuted)
                    .opacity(isTerminating ? 0.5 : 1.0)

                // Close Button or Loading Indicator
                if isTerminating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else if app.isTerminable {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(isHovered ? .red.opacity(0.8) : .secondary.opacity(0.4))
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 24, minHeight: 24)
                    .allowsHitTesting(true)
                    .help("关闭应用")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.8 : 0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(isHovered ? 0.1 : 0.05), lineWidth: 1)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .allowsHitTesting(!isTerminating)

            // 展开的子进程列表
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

    // MARK: - Subviews

    private var expandButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        }) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.labelMuted)
                .frame(width: Self.expandColumnWidth, height: Self.expandColumnWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var childProcessList: some View {
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
#Preview {
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

    VStack(spacing: 12) {
        AppCardView(app: mockApp, isTerminating: false, appManager: AppMemoryManager.shared) {
            // 预览中无需处理关闭动作
        }

        // 单进程应用
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

        AppCardView(app: singleApp, isTerminating: false, appManager: AppMemoryManager.shared) {
            // 预览中无需处理关闭动作
        }
    }
    .padding()
}
#endif
