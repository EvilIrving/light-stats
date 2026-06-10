import SwiftUI

/// Compact 2-col micro-tile grid. Dense info, icon-bottom nav, no big cards.
struct CompactOverviewView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                healthBadge

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    MicroMetricTile(
                        icon: "cpu", label: "CPU",
                        value: String(format: "%.0f%%", monitor.cpuUsage),
                        usage: monitor.cpuUsage,
                        color: theme.colorForUsage(monitor.cpuUsage)
                    )
                    MicroMetricTile(
                        icon: "square.grid.2x2", label: "GPU",
                        value: monitor.gpuUsage.map { String(format: "%.0f%%", $0) } ?? "N/A",
                        usage: monitor.gpuUsage ?? 0,
                        color: theme.colorForUsage(monitor.gpuUsage ?? 0)
                    )
                    MicroMetricTile(
                        icon: "memorychip", label: "MEM",
                        value: String(format: "%.0f%%", monitor.memoryUsage),
                        usage: monitor.memoryUsage,
                        color: theme.accent == .blue ? .purple : theme.accent
                    )
                    MicroMetricTile(
                        icon: "chart.bar.fill", label: "LOAD",
                        value: monitor.loadAverage.displayString,
                        usage: 0,
                        color: theme.secondaryText
                    )
                    MicroMetricTile(
                        icon: "thermometer.medium", label: "TEMP",
                        value: monitor.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "N/A",
                        usage: min(monitor.cpuTemperature ?? 0, 100),
                        color: monitor.cpuTemperature.map { $0 > 75 ? theme.danger : $0 > 55 ? theme.warning : theme.success } ?? theme.secondaryText
                    )
                    MicroMetricTile(
                        icon: "internaldrive.fill", label: "DISK",
                        value: ByteFormatter.formatDisk(monitor.diskAvailable),
                        usage: 0,
                        color: theme.secondaryText
                    )
                }

                MicroNetworkTile(
                    download: ByteFormatter.formatSpeed(monitor.networkDownload),
                    upload: ByteFormatter.formatSpeed(monitor.networkUpload),
                    theme: theme
                )

                if monitor.battery.state != .noBattery {
                    CompactBatteryBadge(battery: monitor.battery, theme: theme)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
    }

    private var healthBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 10))
                .foregroundColor(gradeColor)
            Text("\(monitor.health.score)")
                .font(.system(size: 11, weight: .bold, design: theme.fontDesign))
                .foregroundColor(gradeColor)
            Text("/100")
                .font(.system(size: 9, design: theme.fontDesign))
                .foregroundColor(theme.secondaryText.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(theme.card.opacity(theme.cardOpacity * 0.6))
        )
    }

    private var gradeColor: Color {
        switch monitor.health.grade {
        case .excellent: return theme.success
        case .good: return theme.success.opacity(0.7)
        case .fair: return theme.warning
        case .poor: return .orange
        case .critical: return theme.danger
        }
    }
}

// MARK: - Compact Battery Badge

private struct CompactBatteryBadge: View {
    let battery: BatteryInfo
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: batteryIcon)
                .font(.system(size: 10))
                .foregroundColor(batteryColor)
            Text("\(Int(battery.percent.rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundColor(batteryColor)
            Text(stateText)
                .font(.system(size: 9, design: theme.fontDesign))
                .foregroundColor(theme.secondaryText)
            Spacer()
            if let t = timeText {
                Text(t)
                    .font(.system(size: 9, design: theme.fontDesign))
                    .foregroundColor(theme.secondaryText.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 0.6)
                .fill(theme.card.opacity(theme.cardOpacity * 0.6))
        )
    }

    private var batteryIcon: String {
        switch battery.state {
        case .charging, .charged: return "battery.100.bolt"
        case .noBattery: return "battery.0"
        case .discharging:
            if battery.percent <= 20 { return "battery.25" }
            if battery.percent <= 60 { return "battery.50" }
            return "battery.100"
        }
    }

    private var batteryColor: Color {
        if battery.state == .charging || battery.state == .charged { return theme.success }
        if battery.percent < 10 { return theme.danger }
        if battery.percent < 20 { return theme.warning }
        return theme.success
    }

    private var stateText: String {
        switch battery.state {
        case .charging: return "🔌"
        case .discharging: return ""
        case .charged: return "✓"
        case .noBattery: return ""
        }
    }

    private var timeText: String? {
        guard battery.state != .charged, let m = battery.timeRemaining, m > 0 else { return nil }
        let h = m / 60; let rem = m % 60
        return h > 0 ? "\(h)h\(rem)m" : "\(rem)m"
    }
}
