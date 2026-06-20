//
//  UpdateWindowView.swift
//  Light Stats
//
//  更新窗口内容视图。由 UpdateManager.showWindow() 弹出,所有更新阶段
//  (检查,已最新,发现新版本,下载进度,安装,出错)在此窗口内闭环展示。
//
//  根视图固定宽度、高度随内容动态(配合 NSHostingController.sizingOptions =
//  .preferredContentSize)。更新说明直接整段展示,不用 ScrollView。
//

import SwiftUI

struct UpdateWindowView: View {
    @EnvironmentObject var manager: UpdateManager
    @ObservedObject private var localization = LocalizationManager.shared

    private let contentWidth: CGFloat = 360
    private var appIcon: NSImage? { NSApp.applicationIconImage }

    var body: some View {
        content
            .multilineTextAlignment(.center)
            .frame(width: contentWidth)
            .padding(24)
            .background(Color(nsColor: .windowBackgroundColor))
            .id(localization.currentLanguage)
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
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 阶段视图

    private func statusView(spinner: Bool, text: String) -> some View {
        VStack(spacing: 12) {
            if spinner { ProgressView().scaleEffect(0.8) }
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    private func availableView(_ release: ReleaseInfo) -> some View {
        VStack(spacing: 12) {
            iconView(size: 52)

            Text("update.available.title".localized(release.tagName))
                .font(.system(size: 14, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            if !release.releaseNotes.isEmpty {
                Text(release.releaseNotes)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        }
    }

    private func downloadingView(_ fraction: Double) -> some View {
        VStack(spacing: 12) {
            Text("update.progress.downloading".localized)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .frame(width: 220)
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("update.error.title".localized)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            }
            .padding(.top, 4)
        }
    }
}
