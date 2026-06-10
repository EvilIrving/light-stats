import SwiftUI

// MARK: - Micro Metric Tile (Compact mode)

struct MicroMetricTile: View {
    let icon: String
    let label: String
    let value: String
    let usage: Double
    let color: Color

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 12)

                Text(label)
                    .font(.system(size: 8, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.secondaryText)

                Spacer()

                Text(value)
                    .font(.system(size: 11, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.primaryText)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.primaryText.opacity(0.06))
                        .frame(height: 2.5)
                    Capsule()
                        .fill(color.opacity(0.6))
                        .frame(width: max(3, geo.size.width * min(usage / 100.0, 1.0)), height: 2.5)
                }
            }
            .frame(height: 2.5)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 0.5)
                .fill(theme.card.opacity(theme.cardOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 0.5)
                .stroke(theme.primaryText.opacity(0.04), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Micro Network Tile (Compact mode)

struct MicroNetworkTile: View {
    let download: String
    let upload: String
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "network")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.cyan)
                    .frame(width: 12)

                Text("NET")
                    .font(.system(size: 8, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.secondaryText)

                Spacer()

                HStack(spacing: 6) {
                    HStack(spacing: 1) {
                        Text("↓")
                            .font(.system(size: 7, weight: .bold)).foregroundColor(.cyan)
                        Text(download)
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundColor(theme.primaryText)
                    }
                    HStack(spacing: 1) {
                        Text("↑")
                            .font(.system(size: 7, weight: .bold)).foregroundColor(.cyan)
                        Text(upload)
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundColor(theme.primaryText)
                    }
                }
            }
            Rectangle()
                .fill(theme.primaryText.opacity(0.06))
                .frame(height: 2.5)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 0.5)
                .fill(theme.card.opacity(theme.cardOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 0.5)
                .stroke(theme.primaryText.opacity(0.04), lineWidth: 0.5)
        )
    }
}
