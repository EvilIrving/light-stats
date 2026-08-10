//
//  PermissionAlertCenter.swift
//  Light Stats
//
//  Themed accessibility-permission prompt. Replaces NSAlert so film / noir / glass /
//  bento match the rest of the app (NSAlert always uses system chrome).
//

import AppKit
import SwiftUI

// MARK: - API (call sites keep AccessibilityPermission.presentSettingsAlert)

extension AccessibilityPermission {
    /// 主题化权限引导：打开设置 / 稍后。实现在 Views，不污染 Service 层。
    @MainActor
    static func presentSettingsAlert(title: String, message: String) {
        PermissionAlertCenter.present(title: title, message: message)
    }
}

// MARK: - Panel host

@MainActor
enum PermissionAlertCenter {
    private static var panel: NSPanel?
    private static var hosting: NSHostingView<PermissionAlertView>?

    /// Present a two-button permission guide (Open Settings / Later).
    static func present(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        dismiss()

        let root = PermissionAlertView(
            title: title,
            message: message,
            onOpenSettings: {
                dismiss()
                AccessibilityPermission.openSettings()
            },
            onLater: {
                dismiss()
            }
        )
        let host = NSHostingView(rootView: root)
        host.layout()
        // Fixed layout size — fittingSize can under-measure multiline text.
        let size = NSSize(width: 340, height: 280)
        host.frame = NSRect(origin: .zero, size: size)

        let win = makePanel()
        win.contentView = host
        win.setContentSize(size)
        center(win, size: size)
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            win.animator().alphaValue = 1
        }

        panel = win
        hosting = host
    }

    static func dismiss() {
        guard let win = panel else { return }
        win.orderOut(nil)
        panel = nil
        hosting = nil
    }

    private static func makePanel() -> NSPanel {
        // Borderless: no system titlebar / traffic-light close button.
        // With `.titled + .closable + .fullSizeContentView` the red close control
        // stays in the titlebar chrome and floats over the themed card (see the
        // gray disc above the dialog). Dismiss is via “Later” / Open Settings.
        let win = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.isMovableByWindowBackground = true
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return win
    }

    private static func center(_ win: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        win.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }
}

// MARK: - Content

struct PermissionAlertView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var localization = LocalizationManager.shared

    let title: String
    let message: String
    let onOpenSettings: () -> Void
    let onLater: () -> Void

    private var theme: ThemeTokens { ThemeTokens.tokens(for: settings.appTheme) }
    private var appIcon: NSImage? { NSApp.applicationIconImage }

    var body: some View {
        VStack(spacing: 16) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
            } else {
                Image(systemName: "lock.shield")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 56, height: 56)
            }

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.inkPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)

            HStack(spacing: 10) {
                Button(action: onLater) {
                    Text("update.action.later".localized)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PermissionSecondaryButtonStyle(theme: theme))
                .keyboardShortcut(.cancelAction)

                Button(action: onOpenSettings) {
                    Text("cleaning.permission.openSettings".localized)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PermissionPrimaryButtonStyle(theme: theme))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: 340)
        .foregroundStyle(theme.inkPrimary)
        .background(
            ThemeBackgroundView(
                tokens: theme,
                appearance: settings.themeAppearance(for: settings.appTheme),
                cornerRadius: 14,
                configuresWindow: true,
                fallbackMaterial: .underWindowBackground
            )
            .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.surfaceStroke, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22 + theme.surfaceShadowOpacity * 0.25), radius: 20, y: 8)
        .focusable(false)
        .id("\(localization.currentLanguage.rawValue)/\(settings.appTheme.rawValue)")
        .appThemed(settings.appTheme)
    }
}

// MARK: - Buttons

private struct PermissionPrimaryButtonStyle: ButtonStyle {
    let theme: ThemeTokens

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primaryLabelColor)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accent.opacity(configuration.isPressed ? 0.75 : 1.0))
            )
    }

    private var primaryLabelColor: Color {
        Color(red: 0.97, green: 0.95, blue: 0.92)
    }
}

private struct PermissionSecondaryButtonStyle: ButtonStyle {
    let theme: ThemeTokens

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.inkPrimary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.wellFill.opacity(configuration.isPressed ? 0.85 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.surfaceStroke, lineWidth: 0.5)
            )
    }
}
