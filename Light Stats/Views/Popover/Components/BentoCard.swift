import SwiftUI

struct BentoCard<Content: View, Accessory: View>: View {
    let title: String?
    let icon: String?
    /// 资源目录里的品牌图标名（如 Claude/Codex logo）。设置后优先于 SF Symbol 的 `icon`。
    let assetIcon: String?
    let content: Content
    let headerAccessory: Accessory
    let padding: CGFloat

    init(title: String? = nil,
         icon: String? = nil,
         assetIcon: String? = nil,
         padding: CGFloat = 12,
         @ViewBuilder headerAccessory: () -> Accessory = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.assetIcon = assetIcon
        self.padding = padding
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || icon != nil || assetIcon != nil {
                HStack(spacing: 6) {
                    if let assetIcon = assetIcon {
                        Image(assetIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 13, height: 13)
                    } else if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                    }
                    if let title = title {
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.labelMuted)
                    }
                    Spacer()
                    headerAccessory
                }
            }
            
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
        )
        .compositingGroup()
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}
