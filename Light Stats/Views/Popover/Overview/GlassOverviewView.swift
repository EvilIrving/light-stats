import SwiftUI

/// Glass layout: translucent cards with large corner radius, floating segment nav, spacious.
struct GlassOverviewView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var aiMonitor: AIUsageMonitor
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                healthSection
                metricsGrid
                if monitor.battery.state != .noBattery {
                    batterySection
                }
                statusStrip
                networkSection
                aiCards
                processesSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Sections

    private var healthSection: some View {
        GlassCard {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(gradeColor.opacity(0.3), lineWidth: 3)
                        .frame(width: 48, height: 48)
                    Circle()
                        .trim(from: 0, to: CGFloat(monitor.health.score) / 100)
                        .stroke(gradeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 48, height: 48)
                    Text("\(monitor.health.score)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(gradeColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("health.title".localized)
                        .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                        .foregroundColor(theme.primaryText)
                    Text(gradeText)
                        .font(.system(size: 10, design: theme.fontDesign))
                        .foregroundColor(gradeColor)
                    Text(summaryText)
                        .font(.system(size: 9, design: theme.fontDesign))
                        .foregroundColor(theme.secondaryText.opacity(0.7))
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ], spacing: 14) {
            GlassMetricTile(
                icon: "cpu", label: "CPU",
                value: String(format: "%.0f%%", monitor.cpuUsage),
                usage: monitor.cpuUsage,
                color: theme.colorForUsage(monitor.cpuUsage)
            )
            GlassMetricTile(
                icon: "square.grid.2x2", label: "GPU",
                value: monitor.gpuUsage.map { String(format: "%.0f%%", $0) } ?? "N/A",
                usage: monitor.gpuUsage ?? 0,
                color: theme.colorForUsage(monitor.gpuUsage ?? 0)
            )
            GlassMetricTile(
                icon: "memorychip", label: "MEM",
                value: String(format: "%.0f%%", monitor.memoryUsage),
                usage: monitor.memoryUsage,
                color: .purple,
                subtitle: "\(String(format: "%.1f", Double(monitor.memoryUsed)/1024/1024/1024))G used"
            )
            GlassMetricTile(
                icon: "chart.bar.fill", label: "LOAD",
                value: monitor.loadAverage.displayString,
                usage: 0,
                color: theme.secondaryText
            )
        }
    }

    private var batterySection: some View {
        GlassCard {
            BatteryGlassContent(battery: monitor.battery, temperatureUnit: settings.temperatureUnit)
        }
    }

    private var statusStrip: some View {
        GlassCard {
            HStack(spacing: 12) {
                statusItem(icon: "thermometer.medium", value: monitor.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "N/A")
                Divider().frame(height: 20)
                statusItem(icon: "fanblades.fill", value: monitor.fanSpeed.map { "\($0) RPM" } ?? "N/A")
                Divider().frame(height: 20)
                statusItem(icon: "internaldrive.fill", value: ByteFormatter.formatDisk(monitor.diskAvailable))
            }
            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
            .foregroundColor(theme.secondaryText)
        }
    }

    private func statusItem(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(value)
        }
    }

    private var networkSection: some View {
        GlassCard {
            VStack(spacing: 8) {
                HStack {
                    Label("arrow.down", systemImage: "arrow.down")
                        .font(.system(size: 10, design: theme.fontDesign))
                        .foregroundColor(.cyan)
                    Spacer()
                    Text(ByteFormatter.formatSpeed(monitor.networkDownload))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.primaryText)
                }
                HStack {
                    Label("arrow.up", systemImage: "arrow.up")
                        .font(.system(size: 10, design: theme.fontDesign))
                        .foregroundColor(.cyan)
                    Spacer()
                    Text(ByteFormatter.formatSpeed(monitor.networkUpload))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.primaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var aiCards: some View {
        if settings.aiMonitorClaudeEnabled {
            AIUsageCard(provider: .claude, state: aiMonitor.claudeState)
        }
        if settings.aiMonitorCodexEnabled {
            AIUsageCard(provider: .codex, state: aiMonitor.codexState)
        }
    }

    private var processesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("overview.processes".localized)
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.secondaryText)
                if monitor.topCPUProcesses.isEmpty {
                    Text("overview.loading".localized)
                        .font(.system(size: 10)).foregroundColor(theme.secondaryText)
                } else {
                    ForEach(Array(monitor.topCPUProcesses.prefix(3))) { p in
                        HStack(spacing: 8) {
                            Text(p.name)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Text(p.cpuDisplayString)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(p.cpuPercent < 50 ? theme.success : p.cpuPercent < 80 ? theme.warning : theme.danger)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var gradeColor: Color {
        switch monitor.health.grade {
        case .excellent: return theme.success
        case .good: return theme.success.opacity(0.7)
        case .fair: return theme.warning
        case .poor: return .orange
        case .critical: return theme.danger
        }
    }

    private var gradeText: String {
        switch monitor.health.grade {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .critical: return "Critical"
        }
    }

    private var summaryText: String {
        let parts: [(HealthScore.Dimension, String)] = [
            (.cpu, "CPU"), (.memory, "MEM"), (.disk, "DISK"), (.temperature, "TEMP"), (.diskIO, "I/O")
        ]
        return parts.compactMap { d, label in
            guard let s = monitor.health.breakdown[d.rawValue] else { return nil }
            return "\(label) \(Int(s))"
        }.joined(separator: " · ")
    }
}

// MARK: - Glass Card Wrapper

private struct GlassCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(theme.shadowOpacity), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - Glass Metric Tile

private struct GlassMetricTile: View {
    let icon: String; let label: String; let value: String; let usage: Double; let color: Color
    var subtitle: String?

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.secondaryText)
                Spacer()
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(color)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.secondaryText)
                }
            }
            if usage > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08)).frame(height: 3)
                        Capsule()
                            .fill(color)
                            .frame(width: max(4, geo.size.width * min(usage / 100.0, 1.0)), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 0.85)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 0.85)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Battery Glass Content

private struct BatteryGlassContent: View {
    let battery: BatteryInfo
    let temperatureUnit: SettingsManager.TemperatureUnit
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: batteryIcon)
                    .font(.system(size: 14)).foregroundColor(batteryColor)
                Text("battery.title".localized)
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.secondaryText)
                Spacer()
                Text("\(Int(battery.percent.rounded()))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(batteryColor)
            }
            if battery.state != .noBattery {
                HStack(spacing: 12) {
                    labelValue("Cycles", battery.cycleCount.map { "\($0)" } ?? "—")
                    labelValue("Health", battery.healthPercent.map { "\($0)%" } ?? "—")
                    labelValue("Power", battery.powerWatts.map { String(format: "%.1fW", $0) } ?? "—")
                    labelValue("Temp", battery.temperature.map { temperatureUnit.format($0) } ?? "—")
                }
                .font(.system(size: 9, design: theme.fontDesign))
                .foregroundColor(theme.secondaryText)
            }
        }
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).fontWeight(.semibold).foregroundColor(theme.primaryText)
            Text(label).foregroundColor(theme.secondaryText.opacity(0.7))
        }
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
}
