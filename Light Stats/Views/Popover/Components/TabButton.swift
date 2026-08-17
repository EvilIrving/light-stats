//
//  TabButton.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct TabButton: View {
    @Environment(\.theme) private var theme

    let title: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        let style = theme.chromeStyle
        Text(title)
            .font(style.tabFont(isSelected: isSelected))
            .tracking(style.usesNeonTreatment ? 0.65 : style.usesNightBarTreatment ? 0.18 : 0)
            .textCase(style.usesNeonTreatment ? .uppercase : nil)
            .foregroundStyle(isSelected ? theme.inkPrimary : theme.inkSecondary)
            .shadow(
                color: isSelected && style.usesIlluminatedTreatment
                    ? theme.accent.opacity(style.usesNightBarTreatment ? 0.56 : 0.72)
                    : .clear,
                radius: style.textGlowRadius
            )
            .animation(nil, value: isSelected)
            .padding(.horizontal, style.tabHorizontalPadding)
            .padding(.vertical, style.tabVerticalPadding)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: style.tabCornerRadius, style: .continuous)
                            .fill(theme.tabSelectedFill)
                            .overlay(alignment: .bottom) {
                                if style.usesNightBarTreatment {
                                    Capsule()
                                        .fill(LinearGradient(
                                            colors: [theme.signalAccent, theme.signalGood],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ))
                                        .frame(height: 2)
                                        .padding(.horizontal, 12)
                                        .shadow(color: theme.signalAccent.opacity(0.70), radius: 3)
                                }
                            }
                            .overlay {
                                if style.usesNightBarTreatment {
                                    RoundedRectangle(cornerRadius: style.tabCornerRadius, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    theme.signalAccent.opacity(0.62),
                                                    theme.signalGood.opacity(0.32)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ),
                                            lineWidth: style.surfaceStrokeWidth
                                        )
                                }
                            }
                            .matchedGeometryEffect(id: "ACTIVE_TAB", in: namespace)
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: style.tabCornerRadius, style: .continuous))
            .onTapGesture {
                action()
            }
    }
}
