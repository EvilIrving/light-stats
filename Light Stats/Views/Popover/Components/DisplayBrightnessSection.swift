//
//  DisplayBrightnessSection.swift
//  Light Stats
//

import SwiftUI

struct DisplayBrightnessSection: View {
    @EnvironmentObject private var manager: DisplayControlManager
    @Environment(\.theme) private var theme

    var body: some View {
        PanelSection(title: "display.section".localized) {
            VStack(spacing: 10) {
                ForEach(manager.adjustableDisplays) { display in
                    displayRow(display)
                }
            }
        }
    }

    private func displayRow(_ display: ControlledDisplay) -> some View {
        let isAdjustable = manager.isAdjustable(displayID: display.id)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.metricIcon)
                    .frame(width: 14)
                if let displayName = display.displayName {
                    Text(displayName)
                        .font(theme.chromeStyle.bodyFont)
                        .foregroundStyle(theme.inkPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Text(display.isBuiltIn ? "display.role.builtIn".localized : "display.role.external".localized)
                    if display.capability == .unsupported {
                        Text("·")
                        Text("display.unsupported".localized)
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.inkFaint)
                .lineLimit(1)
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.inkMuted)
                    .frame(width: 14)
                Slider(
                    value: Binding(
                        get: { manager.brightness(displayID: display.id) },
                        set: { manager.setBrightness($0, displayID: display.id) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .controlSize(.small)
                .focusable(false)
                .disabled(!isAdjustable)
                .opacity(isAdjustable ? 1 : 0.4)
                .accessibilityLabel("display.brightness".localized)

                Text("\(Int(manager.brightness(displayID: display.id).rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isAdjustable ? theme.inkSecondary : theme.inkFaint)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .frame(minHeight: 42)
    }
}
