//
//  UpdateWindowView.swift
//  Light Stats
//
//  更新窗口内容视图。由 UpdateManager.showUpdateWindow() 弹出,所有更新阶段
//  (发现新版本,下载进度,安装,出错)在此窗口内闭环展示。
//
//  根视图固定宽度、高度随内容动态(配合 NSHostingController.sizingOptions =
//  .preferredContentSize)。Release notes / 错误文案过长时在滚动区内裁切,
//  操作按钮始终贴在底部可见区域,避免窗口超出屏幕后点不到「更新」。
//

import AppKit
import SwiftUI

struct UpdateWindowView: View {
    @EnvironmentObject var manager: UpdateManager
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    private let contentWidth: CGFloat = 360
    private var appIcon: NSImage? { NSApp.applicationIconImage }
    private var theme: ThemeTokens { ThemeTokens.tokens(for: settings.appTheme) }

    /// Cap scrollable body so the whole window stays within the visible screen.
    /// Leaves room for title bar, icon, title, action row, and padding.
    private var maxScrollBodyHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        // ~200pt for chrome (titlebar + icon + title + buttons + padding + spacing).
        let budget = visible * 0.7 - 200
        return max(100, min(280, budget))
    }

    /// Prefer a tight frame for short text; hard-cap long release notes.
    /// Uses an explicit height (not only maxHeight) so preferredContentSize cannot
    /// grow the NSWindow past the screen and hide the install button.
    private func scrollBodyHeight(for text: String) -> CGFloat {
        let maxHeight = maxScrollBodyHeight
        // ~52 chars/line at 11pt in a 360pt-wide padded column; ~15pt line height.
        let newlineCount = text.reduce(into: 0) { count, char in
            if char == "\n" { count += 1 }
        }
        let wrappedLines = max(1, Int(ceil(Double(text.count) / 52.0)))
        let estimatedLines = max(newlineCount + 1, wrappedLines)
        let estimated = CGFloat(estimatedLines) * 15 + 8
        return min(max(estimated, 48), maxHeight)
    }

    var body: some View {
        content
            .multilineTextAlignment(.center)
            .frame(width: contentWidth)
            .padding(24)
            .foregroundStyle(theme.inkPrimary)
            .background(
                ThemeBackgroundView(
                    tokens: theme,
                    appearance: settings.themeAppearance(for: settings.appTheme),
                    cornerRadius: 0,
                    configuresWindow: true,
                    fallbackMaterial: .underWindowBackground
                )
                .ignoresSafeArea()
            )
            .id("\(localization.currentLanguage.rawValue)/\(settings.appTheme.rawValue)")
            .appThemed(settings.appTheme)
    }

    @ViewBuilder
    private var content: some View {
        switch manager.phase {
        case .available(let release):
            availableView(release)

        case .downloading(let fraction):
            downloadingView(fraction)

        case .installing:
            statusView(spinner: true, text: "update.progress.installing".localized)

        case .error(let message):
            errorView(message)

        case .idle:
            // 窗口仅在发现新版时打开,.idle 不应出现;放一个零尺寸占位保证 switch 完备。
            Color.clear.frame(width: 1, height: 1)
        }
    }

    // MARK: - 通用图标

    @ViewBuilder
    private func iconView(size: CGFloat) -> some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: size))
                .foregroundStyle(theme.inkSecondary)
        }
    }

    // MARK: - 阶段视图

    private func statusView(spinner: Bool, text: String) -> some View {
        VStack(spacing: 12) {
            if spinner { ProgressView().scaleEffect(0.8) }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.inkSecondary)
        }
    }

    private func availableView(_ release: ReleaseInfo) -> some View {
        VStack(spacing: 12) {
            iconView(size: 52)

            Text("update.available.title".localized(release.tagName))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !release.releaseNotes.isEmpty {
                // Explicit height (not only maxHeight): preferredContentSize otherwise
                // measures the full notes ideal size and the install button falls off-screen.
                ScrollView(.vertical, showsIndicators: true) {
                    Text(release.releaseNotes)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: scrollBodyHeight(for: release.releaseNotes))
            }

            availableButtons(release)
                .padding(.top, 2)
        }
    }

    private func availableButtons(_ release: ReleaseInfo) -> some View {
        HStack(spacing: 8) {
            Button { manager.dismissWindow() } label: {
                Text("update.action.later".localized).font(.system(size: 12))
            }
            .buttonStyle(.borderless)

            Button { manager.skipVersion(release) } label: {
                Text("update.action.skip".localized).font(.system(size: 12))
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 8)

            Button { manager.startInstall(release) } label: {
                Text("update.action.install".localized)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 88)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func downloadingView(_ fraction: Double) -> some View {
        VStack(spacing: 12) {
            Text("update.progress.downloading".localized)
                .font(.system(size: 13))
                .foregroundStyle(theme.inkSecondary)
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .frame(width: 220)
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(theme.inkPrimary)
                .monospacedDigit()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(theme.signalAccent)
            Text("update.error.title".localized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.inkPrimary)
            ScrollView(.vertical, showsIndicators: true) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
            }
            .frame(height: scrollBodyHeight(for: message))
            HStack(spacing: 10) {
                Button {
                    if let url = URL(string: "https://github.com/EvilIrving/light-stats/releases/latest") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("update.action.openPage".localized).font(.system(size: 12))
                }
                .buttonStyle(.borderless)

                Button { manager.dismissWindow() } label: {
                    Text("update.action.ok".localized).font(.system(size: 12, weight: .medium))
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
    }
}
