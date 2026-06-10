import SwiftUI

struct BentoCard<Content: View>: View {
    let title: String?
    let icon: String?
    let content: Content
    let padding: CGFloat

    @Environment(\.appTheme) private var theme

    init(title: String? = nil, icon: String? = nil, padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || icon != nil {
                HStack(spacing: 6) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(theme.secondaryText)
                    }
                    if let title = title {
                        Text(title)
                            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                            .foregroundColor(theme.secondaryText)
                    }
                }
            }

            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(theme.card.opacity(theme.cardOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .stroke(theme.primaryText.opacity(0.05), lineWidth: 1)
        )
    }
}
