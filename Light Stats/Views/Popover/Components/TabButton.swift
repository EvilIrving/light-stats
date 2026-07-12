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
        Text(title)
            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? theme.inkPrimary : theme.inkSecondary)
            .animation(nil, value: isSelected)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(theme.tabSelectedFill)
                            .shadow(color: Color.black.opacity(theme.cardShadowOpacity + 0.02), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "ACTIVE_TAB", in: namespace)
                    }
                }
            )
            .contentShape(Capsule())
            .onTapGesture {
                action()
            }
    }
}
