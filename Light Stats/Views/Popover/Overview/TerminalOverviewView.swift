import SwiftUI

/// Terminal layout: green-on-black, monospace, command-line rows with ASCII progress bars.
struct TerminalOverviewView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                divider(thick: true)
                sectionLabel("PROCESSOR")
                cpuRow
                gpuRow
                loadRow
                divider(thick: false)
                sectionLabel("MEMORY")
                memoryRow
                divider(thick: false)
                sectionLabel("I/O")
                diskRow
                networkSection
                if monitor.cpuTemperature != nil || monitor.fanSpeed != nil {
                    divider(thick: false)
                    sectionLabel("THERMAL")
                    if monitor.cpuTemperature != nil { tempRow }
                    if monitor.fanSpeed != nil { fanRow }
                }
                if monitor.battery.state != .noBattery {
                    divider(thick: false)
                    sectionLabel("POWER")
                    batteryRow
                }
                divider(thick: true)
                healthSummary
                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Shared elements

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: theme.fontDesign))
            .foregroundColor(theme.primaryText.opacity(0.35))
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func divider(thick: Bool) -> some View {
        Rectangle()
            .fill(theme.primaryText.opacity(thick ? 0.25 : 0.08))
            .frame(height: 1)
            .padding(.vertical, thick ? 2 : 0)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(theme.danger).frame(width: 6, height: 6)
            Circle().fill(theme.warning).frame(width: 6, height: 6)
            Circle().fill(theme.success).frame(width: 6, height: 6)
            Text("sysinfo — \(formattedTime)")
                .font(.system(size: 9, design: theme.fontDesign))
                .foregroundColor(theme.primaryText.opacity(0.5))
            Spacer()
        }
        .padding(.bottom, 6)
    }

    private var healthSummary: some View {
        HStack(spacing: 0) {
            Text("health ")
                .foregroundColor(theme.primaryText.opacity(0.5))
            Text("\(monitor.health.score)/100")
                .foregroundColor(healthColor)
            Text("  ")
            Text(gradeBar)
                .foregroundColor(healthColor)
        }
        .font(.system(size: 10, design: theme.fontDesign))
        .padding(.top, 4)
    }

    private var gradeBar: String {
        switch monitor.health.grade {
        case .excellent: return "██████████"
        case .good: return "████████░░"
        case .fair: return "██████░░░░"
        case .poor: return "████░░░░░░"
        case .critical: return "██░░░░░░░░"
        }
    }

    private var healthColor: Color {
        switch monitor.health.grade {
        case .excellent: return theme.success
        case .good: return theme.success.opacity(0.7)
        case .fair: return theme.warning
        case .poor: return .orange
        case .critical: return theme.danger
        }
    }

    // MARK: - Row builders

    private var cpuRow: some View {
        metricRow("cpu   ", String(format: "%.0f%%", monitor.cpuUsage), monitor.cpuUsage, theme.colorForUsage(monitor.cpuUsage))
    }

    private var gpuRow: some View {
        let v = monitor.gpuUsage.map { String(format: "%.0f%%", $0) } ?? "N/A"
        let u = monitor.gpuUsage ?? 0
        return metricRow("gpu   ", v, u, theme.colorForUsage(u))
    }

    private var loadRow: some View {
        keyValueRow("load  ", monitor.loadAverage.displayString)
    }

    private var memoryRow: some View {
        HStack(spacing: 0) {
            Text("mem   ").foregroundColor(theme.primaryText.opacity(0.4))
            asciiBar(monitor.memoryUsage, width: 14, color: theme.colorForUsage(monitor.memoryUsage))
            Text(String(format: " %5.0f%%", monitor.memoryUsage)).foregroundColor(theme.colorForUsage(monitor.memoryUsage))
            Text("  [\(String(format: "%.1f", Double(monitor.memoryUsed)/1024/1024/1024))G/\(String(format: "%.0f", Double(monitor.memoryTotal)/1024/1024/1024))G]")
                .foregroundColor(theme.primaryText.opacity(0.35))
        }
        .font(.system(size: 10, design: theme.fontDesign))
        .foregroundColor(theme.primaryText)
    }

    private var diskRow: some View {
        keyValueRow("disk  ", "\(ByteFormatter.formatDisk(monitor.diskAvailable))  R:\(String(format: "%.1f", monitor.diskIO.readMBs))  W:\(String(format: "%.1f", monitor.diskIO.writeMBs)) MB/s")
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            keyValueRow("net ↓ ", ByteFormatter.formatSpeed(monitor.networkDownload))
            keyValueRow("net ↑ ", ByteFormatter.formatSpeed(monitor.networkUpload))
        }
    }

    private var tempRow: some View {
        keyValueRow("temp  ", monitor.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "N/A")
    }

    private var fanRow: some View {
        keyValueRow("fan   ", monitor.fanSpeed.map { "\($0) RPM" } ?? "N/A")
    }

    private var batteryRow: some View {
        let b = monitor.battery
        let extra = b.timeRemaining.map { m in
            let h = m / 60; let r = m % 60
            return h > 0 ? " (\(h)h\(r)m)" : " (\(r)m)"
        } ?? ""
        let status = b.state == .charging ? "⚡" : b.state == .charged ? "✓" : "-"
        return keyValueRow("bat   ", "\(Int(b.percent.rounded()))% \(status)\(extra)")
    }

    private func metricRow(_ label: String, _ value: String, _ usage: Double, _ color: Color) -> some View {
        HStack(spacing: 0) {
            Text(label).foregroundColor(theme.primaryText.opacity(0.4))
            asciiBar(usage, width: 14, color: color)
            Text(value.padding(toLength: 6, withPad: " ", startingAt: 0))
                .foregroundColor(color)
        }
        .font(.system(size: 10, design: theme.fontDesign))
        .foregroundColor(theme.primaryText)
    }

    private func keyValueRow(_ key: String, _ val: String) -> some View {
        HStack(spacing: 0) {
            Text(key).foregroundColor(theme.primaryText.opacity(0.4))
            Text(val)
                .foregroundColor(theme.primaryText)
                .lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 10, design: theme.fontDesign))
        .foregroundColor(theme.primaryText)
    }

    /// ASCII block-char progress bar
    private func asciiBar(_ value: Double, width: Int, color: Color) -> some View {
        let filled = min(Int((value / 100.0) * Double(width)), width)
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, width - filled))
        return Text(bar)
            .foregroundColor(color)
            .font(.system(size: 7, design: .monospaced))
    }

    private var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
