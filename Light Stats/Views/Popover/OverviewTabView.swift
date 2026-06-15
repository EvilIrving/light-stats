//
//  OverviewTabView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import SwiftUI

struct OverviewTabView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var aiMonitor: AIUsageMonitor
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                HealthCard(health: monitor.health)

                // Main Metrics Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    // CPU Card
                    BentoCard(title: "CPU", icon: "cpu") {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(String(format: "%.0f", monitor.cpuUsage))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.labelMuted)
                        }
                        .foregroundColor(colorForUsage(monitor.cpuUsage))
                    }
                    
                    // GPU Card
                    BentoCard(title: "GPU", icon: "square.grid.2x2") {
                        if let gpu = monitor.gpuUsage {
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text(String(format: "%.0f", gpu))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                Text("%")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.labelMuted)
                            }
                            .foregroundColor(colorForUsage(gpu))
                        } else {
                            Text("N/A")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.labelMuted)
                        }
                    }
                    
                    // MEM Card
                    BentoCard(title: "MEM", icon: "memorychip") {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", Double(monitor.memoryUsed) / 1024 / 1024 / 1024))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                Text("/")
                                    .font(.system(size: 12))
                                    .foregroundColor(.labelMuted)
                                Text(String(format: "%.0fGB", Double(monitor.memoryTotal) / 1024 / 1024 / 1024))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.labelMuted)
                            }
                        }
                        .foregroundColor(.purple)
                    }
                    
                    // Load Card
                    BentoCard(title: "overview.load".localized, icon: "chart.bar.fill") {
                        Text(monitor.loadAverage.displayString)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                // Battery Card: 电量 + 状态 + 剩余时间 + 循环/健康/功耗/温度（无电池则不显示）
                if monitor.battery.state != .noBattery {
                    BatteryCard(battery: monitor.battery, temperatureUnit: settings.temperatureUnit)
                }

                // Status Strip
                BentoCard(padding: 10) {
                    VStack(spacing: 8) {
                        HStack {
                            // Temp
                            HStack(spacing: 4) {
                                Image(systemName: "thermometer.medium")
                                Text(monitor.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "N/A")
                            }

                            Spacer()

                            // Fan（图标按转速旋转，封顶避免过快）
                            HStack(spacing: 4) {
                                SpinningFanIcon(rpm: monitor.fanSpeed)
                                Text(monitor.fanSpeed.map { "\($0) RPM" } ?? "N/A")
                            }

                            Spacer()

                            // Disk
                            HStack(spacing: 4) {
                                Image(systemName: "internaldrive.fill")
                                Text(ByteFormatter.formatDisk(monitor.diskAvailable))
                            }
                        }

                        Divider()

                        // Disk I/O 读/写速率
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
                    .foregroundColor(.labelMuted)
                }
                
                // Network Card: 速率 + 本地代理 + 出口节点
                BentoCard(title: "overview.network".localized, icon: "network") {
                    VStack(alignment: .leading, spacing: 8) {
                        // ① 速率行
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

                        // ② 本地代理行
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.labelMuted)
                            Text("network.proxy.title".localized)
                                .foregroundColor(.labelMuted)
                            Spacer()
                            Text(proxyText(monitor.proxyConfig))
                                .foregroundColor(monitor.proxyConfig.isEnabled ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.system(size: 11, design: .monospaced))

                        // ③ 出口行
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .foregroundColor(.labelMuted)
                            Text("network.exit.title".localized)
                                .foregroundColor(.labelMuted)
                            Spacer()
                            exitValueView
                        }
                        .font(.system(size: 11, design: .monospaced))
                    }
                }
                
                // AI Usage Cards (hidden entirely when toggled off in settings)
                if settings.aiMonitorClaudeEnabled {
                    AIUsageCard(provider: .claude, state: aiMonitor.claudeState)
                }
                if settings.aiMonitorCodexEnabled {
                    AIUsageCard(provider: .codex, state: aiMonitor.codexState)
                }

                // Top Processes Section
                BentoCard(title: "overview.processes".localized, icon: "list.bullet") {
                    if monitor.topCPUProcesses.isEmpty {
                        Text("overview.loading".localized)
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(monitor.topCPUProcesses.prefix(3))) { process in
                                ProcessRow(process: process)
                            }
                        }
                    }
                }

                // Core Usage Section
                BentoCard(title: "overview.coreUsage".localized, icon: "cpu.fill") {
                    let sortedCores = getSortedCores()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sortedCores, id: \.index) { core in
                                VStack(spacing: 4) {
                                    Text("\(core.type == .performance ? "P" : "E")\(core.displayIndex)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.labelMuted)
                                    
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.primary.opacity(0.05))
                                            .frame(width: 12, height: 30)
                                        
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(colorForUsage(core.usage))
                                            .frame(width: 12, height: CGFloat(30.0 * (core.usage / 100.0)))
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Helper: Sorted Cores
    
    private struct CoreInfo {
        let index: Int
        let displayIndex: Int
        let usage: Double
        let type: CoreType
    }
    
    /// Get cores sorted by type: P-cores first (numbered 0..N), then E-cores (numbered 0..M)
    private func getSortedCores() -> [CoreInfo] {
        let topology = monitor.coreTopology
        let usages = monitor.coreUsages
        
        guard !usages.isEmpty else { return [] }
        
        // If we have P/E core info, group them
        if topology.performanceCores > 0 && topology.efficiencyCores > 0 {
            var result: [CoreInfo] = []
            let pCount = topology.performanceCores
            let eCount = topology.efficiencyCores
            
            // P-cores first (assume they are the first N cores)
            for i in 0..<min(pCount, usages.count) {
                result.append(CoreInfo(
                    index: i,
                    displayIndex: i,
                    usage: usages[i],
                    type: .performance
                ))
            }
            
            // E-cores after (assume they follow P-cores)
            for i in 0..<min(eCount, usages.count - pCount) {
                let actualIndex = pCount + i
                if actualIndex < usages.count {
                    result.append(CoreInfo(
                        index: actualIndex,
                        displayIndex: i,
                        usage: usages[actualIndex],
                        type: .efficiency
                    ))
                }
            }
            
            return result
        } else {
            // No P/E info, show all cores with unknown type
            return usages.enumerated().map { index, usage in
                CoreInfo(
                    index: index,
                    displayIndex: index,
                    usage: usage,
                    type: .unknown
                )
            }
        }
    }

    private func colorForUsage(_ usage: Double) -> Color {
        if usage < 50 {
            return .green
        } else if usage < 80 {
            return .yellow
        } else {
            return .red
        }
    }

    /// 磁盘 IO 速率文案：MB/s，固定一位小数。
    private func formatMBs(_ mbs: Double) -> String {
        String(format: "%.1f MB/s", mbs)
    }

    // MARK: - Network Helpers

    /// 出口行内容：随设置开关与探测结果切换三态。
    @ViewBuilder
    private var exitValueView: some View {
        if !settings.exitNodeDetectionEnabled {
            Text("network.exit.disabled".localized)
                .foregroundColor(.labelMuted)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if let exit = monitor.exitNode {
            HStack(spacing: 5) {
                Circle()
                    .fill(routeColor(monitor.route))
                    .frame(width: 6, height: 6)
                Text(exitText(exit))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text("network.exit.failed".localized)
                .foregroundColor(.labelMuted)
        }
    }

    /// 本地代理行文案。
    private func proxyText(_ proxy: ProxyConfig) -> String {
        guard proxy.isEnabled else { return "network.proxy.none".localized }
        switch proxy.kind {
        case .tun:
            return proxy.host.map { "TUN \($0)" } ?? "TUN"
        case .http:
            return "HTTP \(proxy.host ?? "")"
        case .https:
            return "HTTPS \(proxy.host ?? "")"
        case .socks:
            return "SOCKS \(proxy.host ?? "")"
        case .pac:
            return "PAC"
        case .none:
            return "network.proxy.none".localized
        }
    }

    /// 出口节点摘要：`ip · city, country · ASN`，缺失字段自动省略。
    private func exitText(_ exit: ExitNode) -> String {
        var parts: [String] = [exit.ip]
        let locality = [exit.city, exit.country].compactMap { $0 }.joined(separator: ", ")
        if !locality.isEmpty { parts.append(locality) }
        if let asn = exit.asn { parts.append(asn) }
        return parts.joined(separator: " · ")
    }

    /// 一致性结论上色：proxied 黄、direct 绿、unknown 灰。
    private func routeColor(_ route: NetworkRoute) -> Color {
        switch route {
        case .direct: return .green
        case .proxied: return .yellow
        case .unknown: return .gray
        }
    }
}

// MARK: - Spinning Fan Icon

/// 风扇图标：按当前转速持续旋转。转速越高转得越快，但封顶到 `maxRevPerSecond`，
/// 避免高转速时「转的飞起」糊成一团。转速为 0 / 未知时静止。
///
/// 用 `TimelineView(.animation)` 逐帧累积角度（而非 repeatForever 动画），
/// 这样转速随 RPM 变化时平滑过渡、无跳变；面板隐藏时 timeline 自动停摆，不耗电。
private struct SpinningFanIcon: View {
    let rpm: Int?

    /// 视觉封顶：最快每秒 1.5 圈。
    private let maxRevPerSecond: Double = 1.5
    /// 达到该转速即封顶（典型笔记本满速约 5000–6000 RPM）。
    private let rpmAtMaxSpeed: Double = 5000

    @State private var angle: Double = 0
    @State private var lastDate: Date = .now

    var body: some View {
        if degreesPerSecond > 0 {
            TimelineView(.animation) { context in
                fanImage
                    .rotationEffect(.degrees(angle))
                    .onChange(of: context.date) { _, now in
                        advance(to: now)
                    }
            }
            .onAppear { lastDate = .now }
        } else {
            fanImage
        }
    }

    private var fanImage: some View {
        Image(systemName: "fanblades.fill")
    }

    /// 当前角速度（度/秒）：RPM 线性映射并封顶。
    private var degreesPerSecond: Double {
        guard let rpm, rpm > 0 else { return 0 }
        let revPerSec = min(Double(rpm) / rpmAtMaxSpeed, 1.0) * maxRevPerSecond
        return revPerSec * 360.0
    }

    /// 按帧间隔累积角度。跳过异常间隔（面板重新显示等）避免突跳。
    private func advance(to now: Date) {
        let dt = now.timeIntervalSince(lastDate)
        lastDate = now
        guard dt > 0, dt < 1 else { return }
        angle = (angle + degreesPerSecond * dt).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - Battery Card

/// 健康分卡片：总分 + 分档 + 各维度简评。
private struct HealthCard: View {
    let health: HealthScore

    var body: some View {
        BentoCard(title: "health.title".localized, icon: "heart.text.square") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(health.score)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(gradeColor)
                    Text("/ 100")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.labelMuted)
                    Text(gradeText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(gradeColor)
                        .padding(.leading, 4)
                    Spacer()
                    Circle()
                        .fill(gradeColor)
                        .frame(width: 10, height: 10)
                }

                Text(summaryText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.labelMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var gradeText: String {
        switch health.grade {
        case .excellent: return "health.grade.excellent".localized
        case .good: return "health.grade.good".localized
        case .fair: return "health.grade.fair".localized
        case .poor: return "health.grade.poor".localized
        case .critical: return "health.grade.critical".localized
        }
    }

    private var gradeColor: Color {
        switch health.grade {
        case .excellent: return .green
        case .good: return Color(red: 0.35, green: 0.78, blue: 0.42)
        case .fair: return .yellow
        case .poor: return .orange
        case .critical: return .red
        }
    }

    private var summaryText: String {
        let dimensions: [(HealthScore.Dimension, String)] = [
            (.cpu, "health.dimension.cpu".localized),
            (.memory, "health.dimension.memory".localized),
            (.load, "health.dimension.load".localized),
            (.temperature, "health.dimension.temperature".localized),
            (.gpu, "health.dimension.gpu".localized),
            (.battery, "health.dimension.battery".localized),
            (.diskIO, "health.dimension.diskIO".localized)
        ]

        return dimensions.compactMap { dimension, label in
            guard let score = health.breakdown[dimension.rawValue] else { return nil }
            return "\(label) \(levelText(for: dimension, score: score))"
        }
        .joined(separator: " · ")
    }

    private func levelText(for dimension: HealthScore.Dimension, score: Double) -> String {
        if dimension == .temperature {
            if score >= 85 { return "health.level.normal".localized }
            if score >= 60 { return "health.level.warm".localized }
            return "health.level.hot".localized
        }

        if score >= 85 { return "health.level.low".localized }
        if score >= 60 { return "health.level.medium".localized }
        return "health.level.high".localized
    }
}

/// 电池概览卡：电量百分比（大字+上色）、状态、剩余时间；副行循环/健康/功耗/温度。
/// 无电池机型（台式 Mac）优雅显示 N/A。
private struct BatteryCard: View {
    let battery: BatteryInfo
    let temperatureUnit: SettingsManager.TemperatureUnit

    var body: some View {
        BentoCard(title: "battery.title".localized, icon: batteryIcon) {
            if battery.state == .noBattery {
                Text("battery.na".localized)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.labelMuted)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // 主行：电量大字 + 状态 + 剩余时间
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", battery.percent))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(batteryColor)
                        Text("%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.labelMuted)

                        Text(stateText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.labelMuted)
                            .padding(.leading, 4)

                        Spacer()

                        if let time = timeRemainingText {
                            Text(time)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.labelMuted)
                        }
                    }

                    Divider()

                    // 副行：循环 / 健康 / 功耗 / 温度
                    HStack {
                        SubStat(label: "battery.cycles".localized, value: battery.cycleCount.map { "\($0)" })
                        Spacer()
                        SubStat(label: "battery.health".localized, value: battery.healthPercent.map { "\($0)%" })
                        Spacer()
                        SubStat(label: "battery.power".localized, value: battery.powerWatts.map { String(format: "%.1fW", $0) })
                        Spacer()
                        SubStat(label: "battery.temp".localized, value: battery.temperature.map { temperatureUnit.format($0) })
                    }
                }
            }
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
        if battery.state == .charging || battery.state == .charged { return .green }
        if battery.percent < 10 { return .red }
        if battery.percent < 20 { return .yellow }
        return .green
    }

    private var stateText: String {
        switch battery.state {
        case .charging: return "battery.state.charging".localized
        case .discharging: return "battery.state.discharging".localized
        case .charged: return "battery.state.charged".localized
        case .noBattery: return ""
        }
    }

    /// 剩余/充满时间文案。计算中或已充满则不显示。
    private var timeRemainingText: String? {
        guard battery.state != .charged, let minutes = battery.timeRemaining, minutes > 0 else {
            return nil
        }
        let h = minutes / 60
        let m = minutes % 60
        let hm = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        let key = battery.state == .charging ? "battery.timeToFull" : "battery.timeLeft"
        return String(format: key.localized, hm)
    }
}

/// 电池副行的小统计项：值在上、标签在下；缺值显示「—」。
private struct SubStat: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(value ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.labelMuted)
        }
    }
}

// MARK: - Process Row

private struct ProcessRow: View {
    let process: TopProcess
    
    var color: Color {
        if process.cpuPercent < 30 {
            return .green
        } else if process.cpuPercent < 70 {
            return .yellow
        } else {
            return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Process name
            Text(process.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Mini progress bar (5 blocks)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let threshold = Double(i + 1) * 20
                    Rectangle()
                        .fill(process.cpuPercent >= threshold - 10 ? color : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 10)
                        .cornerRadius(2)
                }
            }
            
            // CPU percentage
            Text(process.cpuDisplayString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 50, alignment: .trailing)
        }
    }
}
