import SwiftUI

/// Classic Bento-card layout — the original OverviewTabView content extracted for dispatch.
struct ClassicOverviewView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var aiMonitor: AIUsageMonitor
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                healthSection
                metricsGrid
                if monitor.battery.state != .noBattery {
                    BatteryCard(battery: monitor.battery, temperatureUnit: settings.temperatureUnit)
                }
                statusStrip
                networkCard
                aiCards
                processesSection
                coreUsageSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private var healthSection: some View {
        HealthCard(health: monitor.health)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            BentoCard(title: "CPU", icon: "cpu") {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", monitor.cpuUsage))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("%").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                }
                .foregroundColor(theme.colorForUsage(monitor.cpuUsage))
            }

            BentoCard(title: "GPU", icon: "square.grid.2x2") {
                if let gpu = monitor.gpuUsage {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", gpu))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("%").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    }
                    .foregroundColor(theme.colorForUsage(gpu))
                } else {
                    Text("N/A").font(.system(size: 20, weight: .bold)).foregroundColor(.secondary)
                }
            }

            BentoCard(title: "MEM", icon: "memorychip") {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", Double(monitor.memoryUsed) / 1024 / 1024 / 1024))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("/").font(.system(size: 12)).foregroundColor(.secondary)
                        Text(String(format: "%.0fGB", Double(monitor.memoryTotal) / 1024 / 1024 / 1024))
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.purple)
            }

            BentoCard(title: "overview.load".localized, icon: "chart.bar.fill") {
                Text(monitor.loadAverage.displayString)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private var statusStrip: some View {
        BentoCard(padding: 10) {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.medium")
                        Text(monitor.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "N/A")
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        SpinningFanIcon(rpm: monitor.fanSpeed)
                        Text(monitor.fanSpeed.map { "\($0) RPM" } ?? "N/A")
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive.fill")
                        Text(ByteFormatter.formatDisk(monitor.diskAvailable))
                    }
                }
                Divider()
                HStack {
                    Text("overview.diskIO".localized)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text(formatMBs(monitor.diskIO.readMBs))
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text(formatMBs(monitor.diskIO.writeMBs))
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
        }
    }

    private var networkCard: some View {
        BentoCard(title: "overview.network".localized, icon: "network") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text(ByteFormatter.formatSpeed(monitor.networkUpload))
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text(ByteFormatter.formatSpeed(monitor.networkDownload))
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.cyan)
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield").foregroundColor(.secondary)
                    Text("network.proxy.title".localized).foregroundColor(.secondary)
                    Spacer()
                    Text(proxyText(monitor.proxyConfig))
                        .foregroundColor(monitor.proxyConfig.isEnabled ? .primary : .secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .font(.system(size: 11, design: .monospaced))
                HStack(spacing: 4) {
                    Image(systemName: "globe").foregroundColor(.secondary)
                    Text("network.exit.title".localized).foregroundColor(.secondary)
                    Spacer()
                    exitValueView
                }
                .font(.system(size: 11, design: .monospaced))
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
        BentoCard(title: "overview.processes".localized, icon: "list.bullet") {
            if monitor.topCPUProcesses.isEmpty {
                Text("overview.loading".localized).font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(monitor.topCPUProcesses.prefix(3))) { process in
                        ProcessRow(process: process)
                    }
                }
            }
        }
    }

    private var coreUsageSection: some View {
        let cores = getSortedCores()
        guard !cores.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            BentoCard(title: "overview.coreUsage".localized, icon: "cpu.fill") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cores, id: \.index) { core in
                            VStack(spacing: 4) {
                                Text("\(core.type == .performance ? "P" : "E")\(core.displayIndex)")
                                    .font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.primary.opacity(0.05)).frame(width: 12, height: 30)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(theme.colorForUsage(core.usage))
                                        .frame(width: 12, height: CGFloat(30.0 * (core.usage / 100.0)))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        )
    }

    @ViewBuilder
    private var exitValueView: some View {
        if !settings.exitNodeDetectionEnabled {
            Text("network.exit.disabled".localized).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)
        } else if let exit = monitor.exitNode {
            HStack(spacing: 5) {
                Circle().fill(routeColor(monitor.route)).frame(width: 6, height: 6)
                Text(exitText(exit)).foregroundColor(.primary).lineLimit(1).truncationMode(.middle)
            }
        } else {
            Text("network.exit.failed".localized).foregroundColor(.secondary)
        }
    }

    private func proxyText(_ proxy: ProxyConfig) -> String {
        guard proxy.isEnabled else { return "network.proxy.none".localized }
        switch proxy.kind {
        case .tun: return proxy.host.map { "TUN \($0)" } ?? "TUN"
        case .http: return "HTTP \(proxy.host ?? "")"
        case .https: return "HTTPS \(proxy.host ?? "")"
        case .socks: return "SOCKS \(proxy.host ?? "")"
        case .pac: return "PAC"
        case .none: return "network.proxy.none".localized
        }
    }

    private func exitText(_ exit: ExitNode) -> String {
        var parts: [String] = [exit.ip]
        let locality = [exit.city, exit.country].compactMap { $0 }.joined(separator: ", ")
        if !locality.isEmpty { parts.append(locality) }
        if let asn = exit.asn { parts.append(asn) }
        return parts.joined(separator: " · ")
    }

    private func routeColor(_ route: NetworkRoute) -> Color {
        switch route { case .direct: return .green; case .proxied: return .yellow; case .unknown: return .gray }
    }

    private func formatMBs(_ mbs: Double) -> String {
        String(format: "%.1f MB/s", mbs)
    }

    // MARK: - Core sorting

    private struct CoreInfo {
        let index: Int; let displayIndex: Int; let usage: Double; let type: CoreType
    }

    private func getSortedCores() -> [CoreInfo] {
        let topology = monitor.coreTopology
        let usages = monitor.coreUsages
        guard !usages.isEmpty else { return [] }
        if topology.performanceCores > 0 && topology.efficiencyCores > 0 {
            var result: [CoreInfo] = []
            let pCount = topology.performanceCores
            for i in 0..<min(pCount, usages.count) {
                result.append(CoreInfo(index: i, displayIndex: i, usage: usages[i], type: .performance))
            }
            for i in 0..<min(topology.efficiencyCores, usages.count - pCount) {
                let idx = pCount + i
                if idx < usages.count {
                    result.append(CoreInfo(index: idx, displayIndex: i, usage: usages[idx], type: .efficiency))
                }
            }
            return result
        }
        return usages.enumerated().map { CoreInfo(index: $0, displayIndex: $0, usage: $1, type: .unknown) }
    }
}
