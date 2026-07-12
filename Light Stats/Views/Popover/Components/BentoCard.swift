import SwiftUI

/// Classic raised card chrome used by the **Bento Grid** theme (original product look).
struct BentoCard<Content: View, Accessory: View>: View {
    @Environment(\.theme) private var theme

    let title: String?
    let icon: String?
    /// Asset catalog brand icon (e.g. Claude/Codex). Preferred over SF Symbol `icon`.
    let assetIcon: String?
    let content: Content
    let headerAccessory: Accessory
    let padding: CGFloat
    let fixedHeight: CGFloat?

    init(
        title: String? = nil,
        icon: String? = nil,
        assetIcon: String? = nil,
        padding: CGFloat = 12,
        fixedHeight: CGFloat? = nil,
        @ViewBuilder headerAccessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.assetIcon = assetIcon
        self.padding = padding
        self.fixedHeight = fixedHeight
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || icon != nil || assetIcon != nil {
                HStack(spacing: 6) {
                    if let assetIcon {
                        Image(assetIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 13, height: 13)
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkMuted)
                    }
                    if let title {
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.inkMuted)
                    }
                    Spacer()
                    headerAccessory
                }
            }

            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: fixedHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surfaceFill)
        )
        .compositingGroup()
        .shadow(color: .black.opacity(theme.surfaceShadowOpacity), radius: 3, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.surfaceStroke, lineWidth: 0.5)
        )
    }
}
