import SwiftUI
import AppKit

struct AboutView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    private var theme: ThemeTokens { ThemeTokens.tokens(for: settings.appTheme) }

    private let appName: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Light Stats"
    }()

    private var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(marketing) (\(build))"
    }

    private var appIcon: NSImage? {
        NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

            // App Icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .foregroundStyle(theme.inkSecondary)
            }

            Spacer().frame(height: 20)

            // App Name
            Text(appName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.inkPrimary)

            Spacer().frame(height: 6)

            // Version
            Text(version)
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary)

            Spacer().frame(height: 12)

            // Check for Updates
            Button {
                UpdateManager.shared.check(userInitiated: true)
            } label: {
                HStack(spacing: 5) {
                    if updateManager.isChecking {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    }
                    Text((updateManager.isChecking ? "update.checking" : "update.checkButton").localized)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.accent)
            .disabled(updateManager.isChecking)

            Spacer().frame(height: 24)

            // Links
            HStack(spacing: 12) {
                LinkButton(
                    icon: "github-mark",
                    title: "GitHub",
                    url: "https://github.com/EvilIrving/light-stats"
                )
                LinkButton(
                    icon: "globe",
                    title: "Website",
                    url: "https://evilirving.github.io/light-stats/"
                )
                LinkButton(
                    icon: "questionmark.circle",
                    title: "Support",
                    url: "https://evilirving.github.io/light-stats/#support"
                )
            }

            Spacer().frame(height: 24)

            // Copyright
            Text(copyright)
                .font(.system(size: 10))
                .foregroundStyle(theme.inkFaint)

            Spacer().frame(height: 28)
        }
        .frame(width: 280)
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
        .focusable(false)
    }

    private var copyright: String {
        let year = Calendar.current.component(.year, from: Date())
        return "Copyright © \(year). All rights reserved."
    }
}

// MARK: - Link Button

struct LinkButton: View {
    @Environment(\.theme) private var theme

    let icon: String
    let title: String
    let url: String

    @State private var isHovered = false

    var body: some View {
        Button {
            if let nsurl = URL(string: url) {
                NSWorkspace.shared.open(nsurl)
            }
        } label: {
            VStack(spacing: 6) {
                linkIcon
                    .font(.system(size: 20))
                    .foregroundStyle(isHovered ? theme.inkPrimary : theme.inkSecondary)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovered ? theme.inkPrimary : theme.inkSecondary)
            }
            .frame(width: 72, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? theme.rowHoverFill : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var linkIcon: some View {
        if icon == "github-mark" {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
        } else {
            Image(systemName: icon)
        }
    }
}

#if DEBUG
#Preview {
    AboutView()
}
#endif
