//
//  OverviewTabView.swift
//  Light Stats
//
//  Two layouts:
//  - Bento Grid theme → classic raised cards + 2×2 metric tiles
//  - Film / Glass / Noir → instrument readout (sections + hairlines)
//

import SwiftUI

struct OverviewTabView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var aiMonitor: AIUsageMonitor
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsManager.shared

    private let quickStatCardHeight: CGFloat = 62

    var body: some View {
        ScrollView(showsIndicators: false) {
            if theme.theme.usesBentoLayout {
                bentoContent
            } else {
                instrumentContent
            }
        }
        // Claim the full tab bounds for hit testing so transparent gaps between
        // instrument rows still route wheel events to this ScrollView (not through
        // the non-opaque panel to the window behind — mesh themes especially).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Instrument layout

    private var instrumentContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            healthSection
            PanelDivider().padding(.vertical, 10)
            // CPU / GPU / Load / MEM — one readout group (not two section headers).
            resourcesSection
            if monitor.battery.state != .noBattery {
                PanelDivider().padding(.vertical, 10)
                batterySection
            }
            PanelDivider().padding(.vertical, 10)
            thermalStrip
            PanelDivider().padding(.vertical, 10)
            aiSection
            networkSection
            PanelDivider().padding(.vertical, 10)
            processesSection
            PanelDivider().padding(.vertical, 10)
            coresSection
            PanelDivider().padding(.vertical, 12)
            actionRows
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }

    // MARK: - Bento Grid layout (original)

    private var bentoContent: some View {
        VStack(spacing: 12) {
            BentoCard(title: "health.title".localized, icon: "stethoscope", padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HeroReadout(
                        value: "\(monitor.health.score)",
                        unit: "/ 100",
                        caption: gradeText(monitor.health.grade),
                        valueColor: gradeColor(monitor.health.grade)
                    )
                    healthSummary
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.inkMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 8) {
                QuickStatCard(title: "CPU", svgIcon: .cpu, height: quickStatCardHeight, trend: cpuTrend) {
                    metricPercent(monitor.cpuUsage)
                }
                QuickStatCard(title: "GPU", svgIcon: .gpu, height: quickStatCardHeight, trend: gpuTrend) {
                    if let gpu = monitor.gpuUsage {
                        metricPercent(gpu)
                    } else {
                        Text("—")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(theme.inkMuted)
                    }
                }
                QuickStatCard(title: "MEM", svgIcon: .memory, height: quickStatCardHeight, trend: memoryTrend) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", Double(monitor.memoryUsed) / 1024 / 1024 / 1024))
                            .font(.system(size: 20, weight: useFlatColors ? .regular : .bold, design: .rounded))
                        Text("/")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkMuted)
                        Text(String(format: "%.0fGB", Double(monitor.memoryTotal) / 1024 / 1024 / 1024))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.inkMuted)
                    }
                    .foregroundStyle(useFlatColors ? theme.inkPrimary : colorForUsage(monitor.memoryUsage))
                }
                QuickStatCard(
                    title: "overview.load".localized,
                    icon: "speedometer",
                    height: quickStatCardHeight,
                    trend: loadTrend
                ) {
                    Text(monitor.loadAverage.displayString)
                        .font(.system(size: 14, weight: useFlatColors ? .regular : .semibold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(useFlatColors ? theme.inkPrimary : colorForUsage(loadUsagePercent))
                }
            }

            if monitor.battery.state != .noBattery {
                BentoCard(title: "battery.title".localized, icon: batteryIcon(monitor.battery)) {
                    bentoBatteryInner
                }
            }

            BentoCard(padding: 10) {
                systemMetricsGrid
            }

            bentoAICard
            bentoNetworkCard
            bentoProcessesCard
            bentoCoresCard
            actionRows
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var bentoAICard: some View {
        let aiProviders: [(AIProvider, ProviderFetchState)] = [
            settings.aiMonitorClaudeEnabled ? (.claude, aiMonitor.claudeState) : nil,
            settings.aiMonitorCodexEnabled ? (.codex, aiMonitor.codexState) : nil,
            settings.aiMonitorGeminiEnabled ? (.gemini, aiMonitor.geminiState) : nil,
        ].compactMap { $0 }

        if !aiProviders.isEmpty {
            BentoCard {
                VStack(spacing: 10) {
                    ForEach(aiProviders, id: \.0.rawValue) { provider, state in
                        AIProviderCompactRow(
                            provider: provider,
                            state: state,
                            useFlatColors: useFlatColors
                        )
                    }
                }
            }
        }
    }

    private var bentoNetworkCard: some View {
        BentoCard(title: "overview.network".localized, svgIcon: .network) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text(ByteFormatter.formatSpeed(monitor.networkUpload))
                    }
                    .foregroundStyle(theme.signalAccent)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text(ByteFormatter.formatSpeed(monitor.networkDownload))
                    }
                    .foregroundStyle(theme.signalInfo)
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))

                if monitor.trends.networkUp.count > 1 {
                    Sparkline(series: [
                        SparklineSeries(values: monitor.trends.networkDown, color: theme.signalInfo),
                        SparklineSeries(values: monitor.trends.networkUp, color: theme.signalAccent)
                    ])
                    .frame(height: 24)
                }

                Divider()

                MetaRow(
                    svgIcon: .proxy,
                    label: "network.proxy.title".localized,
                    value: proxyText(monitor.proxyConfig),
                    valueColor: monitor.proxyConfig.isEnabled ? theme.inkPrimary : theme.inkSecondary
                )

                if settings.exitNodeDetectionEnabled {
                    MetaRow(
                        icon: "globe",
                        label: "network.exit.title".localized,
                        value: exitDisplayText
                    )
                }
            }
        }
    }

    private var bentoProcessesCard: some View {
        BentoCard(title: "overview.processes".localized, svgIcon: .processes) {
            if monitor.topCPUProcesses.isEmpty {
                Text("overview.loading".localized)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkMuted)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(monitor.topCPUProcesses.prefix(3))) { process in
                        ProcessRow(process: process, useFlatColors: useFlatColors)
                    }
                }
            }
        }
    }

    private var bentoCoresCard: some View {
        BentoCard(title: "overview.coreUsage".localized, icon: "circle.grid.3x3") {
            let sortedCores = getSortedCores()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedCores, id: \.index) { core in
                        VStack(spacing: 4) {
                            Text("\(core.type == .performance ? "P" : "E")\(core.displayIndex)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.inkMuted)

                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.wellFill)
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

    private var bentoBatteryInner: some View {
        let battery = monitor.battery
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", battery.percent))
                    .font(.system(size: 24, weight: useFlatColors ? .regular : .bold, design: .rounded))
                    .foregroundStyle(batteryColor(battery))
                Text("%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.inkMuted)
                Text(batteryStateText(battery))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.inkMuted)
                    .padding(.leading, 4)
                Spacer()
                if let time = batteryTimeText(battery) {
                    Text(time)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.inkMuted)
                }
            }
            Divider()
            HStack {
                SubStat(label: "battery.cycles".localized, value: battery.cycleCount.map { "\($0)" })
                Spacer()
                SubStat(label: "battery.health".localized, value: battery.healthPercent.map { "\($0)%" })
                Spacer()
                SubStat(
                    label: "battery.power".localized,
                    value: battery.powerWatts.map { String(format: "%.1fW", $0) }
                )
                Spacer()
                SubStat(
                    label: "battery.temp".localized,
                    value: battery.temperature.map { settings.temperatureUnit.format($0) }
                )
            }
        }
    }

    // MARK: - Health

    private var healthSection: some View {
        // Instrument themes (film / glass / noir): title only — no section glyph.
        // Bento keeps card icons on BentoCard.
        PanelSection(title: "health.title".localized) {
            VStack(alignment: .leading, spacing: 6) {
                HeroReadout(
                    value: "\(monitor.health.score)",
                    unit: "/ 100",
                    caption: gradeText(monitor.health.grade),
                    valueColor: gradeColor(monitor.health.grade)
                )
                healthSummary
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.inkMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Resources (CPU / GPU / Load / MEM as one group)

    private var resourcesSection: some View {
        PanelSection(title: "overview.resources".localized) {
            VStack(spacing: 2) {
                MetricRow(label: "CPU", svgIcon: .cpu, trend: cpuTrend) {
                    metricPercent(monitor.cpuUsage)
                }
                MetricRow(label: "GPU", svgIcon: .gpu, trend: gpuTrend) {
                    if let gpu = monitor.gpuUsage {
                        metricPercent(gpu)
                    } else {
                        Text("—")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.inkMuted)
                    }
                }
                MetricRow(label: "overview.load".localized, icon: "speedometer", trend: loadTrend) {
                    Text(monitor.loadAverage.displayString)
                        .font(.system(size: 13, weight: useFlatColors ? .regular : .semibold, design: .monospaced))
                        .foregroundStyle(useFlatColors ? theme.inkPrimary : colorForUsage(loadUsagePercent))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                MetricRow(label: "MEM", svgIcon: .memory, trend: memoryTrend) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", Double(monitor.memoryUsed) / 1024 / 1024 / 1024))
                            .font(.system(size: 16, weight: useFlatColors ? .regular : .bold, design: .rounded))
                        Text("/")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.inkMuted)
                        Text(String(format: "%.0fGB", Double(monitor.memoryTotal) / 1024 / 1024 / 1024))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.inkMuted)
                    }
                    .foregroundStyle(useFlatColors ? theme.inkPrimary : colorForUsage(monitor.memoryUsage))
                }
            }
        }
    }

    // MARK: - Battery

    private var batterySection: some View {
        let battery = monitor.battery
        return PanelSection(title: "battery.title".localized) {
            VStack(alignment: .leading, spacing: 8) {
                HeroReadout(
                    value: String(format: "%.0f", battery.percent),
                    unit: "%",
                    caption: batteryStateText(battery),
                    valueColor: batteryColor(battery)
                ) {
                    if let time = batteryTimeText(battery) {
                        Text(time)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.inkMuted)
                    }
                }

                HStack {
                    SubStat(label: "battery.cycles".localized, value: battery.cycleCount.map { "\($0)" })
                    Spacer()
                    SubStat(label: "battery.health".localized, value: battery.healthPercent.map { "\($0)%" })
                    Spacer()
                    SubStat(
                        label: "battery.power".localized,
                        value: battery.powerWatts.map { String(format: "%.1fW", $0) }
                    )
                    Spacer()
                    SubStat(
                        label: "battery.temp".localized,
                        value: battery.temperature.map { settings.temperatureUnit.format($0) }
                    )
                }
            }
        }
    }

    // MARK: - Thermal / disk strip

    /// Three equal columns (temp | fan | disk) with I/O row aligned under them —
    /// same vertical grid discipline as Bento cards.
    private var thermalStrip: some View {
        PanelSection(title: "overview.system".localized) {
            systemMetricsGrid
        }
    }

    /// Shared by instrument + bento system blocks.
    /// Three equal columns, each a VStack (sensor on top, I/O line below).
    /// Leading-aligned so the first column sits flush with the section title (no leading gap).
    private var systemMetricsGrid: some View {
        HStack(alignment: .top, spacing: 8) {
            systemMetricColumn(
                top: {
                    systemSVGIconValue(
                        svgIcon: .temperature,
                        text: monitor.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "—"
                    )
                },
                bottom: {
                    Text("overview.diskIO".localized)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            )
            systemMetricColumn(
                top: {
                    HStack(spacing: 4) {
                        SpinningFanIcon(rpm: monitor.fanSpeed)
                        Text(monitor.fanSpeed.map { "\($0) RPM" } ?? "—")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.inkMuted)
                },
                bottom: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                        Text(formatMBs(monitor.diskIO.readMBs))
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            )
            systemMetricColumn(
                top: {
                    systemSVGIconValue(
                        svgIcon: .disk,
                        text: ByteFormatter.formatDisk(monitor.diskAvailable)
                    )
                },
                bottom: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                        Text(formatMBs(monitor.diskIO.writeMBs))
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            )
        }
    }

    /// Equal-width column; content hugs the leading edge (no centered inset).
    private func systemMetricColumn<Top: View, Bottom: View>(
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            top()
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            bottom()
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func systemIconValue(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(theme.inkMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func systemSVGIconValue(svgIcon: AppSVGIcon, text: String) -> some View {
        HStack(spacing: 4) {
            SVGIcon(svgIcon, size: 11)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(theme.inkMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - AI

    @ViewBuilder
    private var aiSection: some View {
        let aiProviders: [(AIProvider, ProviderFetchState)] = [
            settings.aiMonitorClaudeEnabled ? (.claude, aiMonitor.claudeState) : nil,
            settings.aiMonitorCodexEnabled ? (.codex, aiMonitor.codexState) : nil,
            settings.aiMonitorGeminiEnabled ? (.gemini, aiMonitor.geminiState) : nil,
        ].compactMap { $0 }

        if !aiProviders.isEmpty {
            PanelSection(title: "aiUsage.title".localized) {
                VStack(spacing: 10) {
                    ForEach(aiProviders, id: \.0.rawValue) { provider, state in
                        AIProviderCompactRow(
                            provider: provider,
                            state: state,
                            useFlatColors: useFlatColors
                        )
                    }
                }
            }
            PanelDivider().padding(.vertical, 10)
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        // Instrument layout: section titles are text-only; Bento keeps card icons.
        PanelSection(title: "overview.network".localized) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text(ByteFormatter.formatSpeed(monitor.networkUpload))
                    }
                    .foregroundStyle(theme.signalAccent)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text(ByteFormatter.formatSpeed(monitor.networkDownload))
                    }
                    .foregroundStyle(theme.signalInfo)
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))

                if monitor.trends.networkUp.count > 1 {
                    Sparkline(series: [
                        SparklineSeries(values: monitor.trends.networkDown, color: theme.signalInfo),
                        SparklineSeries(values: monitor.trends.networkUp, color: theme.signalAccent)
                    ])
                    .frame(height: 22)
                    .opacity(0.7)
                }

                MetaRow(
                    svgIcon: .proxy,
                    label: "network.proxy.title".localized,
                    value: proxyText(monitor.proxyConfig),
                    valueColor: monitor.proxyConfig.isEnabled ? theme.inkPrimary : theme.inkSecondary
                )

                if settings.exitNodeDetectionEnabled {
                    MetaRow(
                        icon: "globe",
                        label: "network.exit.title".localized,
                        value: exitDisplayText
                    )
                }
            }
        }
    }

    // MARK: - Processes

    private var processesSection: some View {
        PanelSection(title: "overview.processes".localized) {
            if monitor.topCPUProcesses.isEmpty {
                Text("overview.loading".localized)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkMuted)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(monitor.topCPUProcesses.prefix(3))) { process in
                        ProcessRow(process: process, useFlatColors: useFlatColors)
                    }
                }
            }
        }
    }

    // MARK: - Cores

    private var coresSection: some View {
        PanelSection(title: "overview.coreUsage".localized) {
            let sortedCores = getSortedCores()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedCores, id: \.index) { core in
                        VStack(spacing: 4) {
                            Text("\(core.type == .performance ? "P" : "E")\(core.displayIndex)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.inkFaint)

                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.wellFill)
                                    .frame(width: 10, height: 28)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorForUsage(core.usage))
                                    .frame(width: 10, height: CGFloat(28.0 * (core.usage / 100.0)))
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Actions

    private var actionRows: some View {
        VStack(spacing: 0) {
            ActionRow(
                icon: "info.circle",
                title: "popover.action.about".localized,
                action: openAbout,
                foregroundColor: theme.inkSecondary
            )
            ActionRow(
                icon: "power",
                title: "popover.action.quit".localized,
                action: { NSApp.terminate(nil) },
                foregroundColor: theme.signalBad.opacity(0.9)
            )
        }
    }

    // MARK: - Small builders

    private func metricPercent(_ usage: Double) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(String(format: "%.0f", usage))
                .font(.system(size: 16, weight: useFlatColors ? .regular : .bold, design: .rounded))
            Text("%")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.inkMuted)
        }
        .foregroundStyle(useFlatColors ? theme.inkPrimary : colorForUsage(usage))
    }

    // MARK: - Trends / colors

    private var useFlatColors: Bool { settings.useFlatColors }

    private var loadUsagePercent: Double {
        let coreCount = monitor.coreTopology.totalCores > 0
            ? monitor.coreTopology.totalCores
            : max(monitor.coreUsages.count, 1)
        return min(100, max(0, monitor.loadAverage.load1 / Double(coreCount) * 100))
    }

    private var cpuTrend: SparklineSeries {
        SparklineSeries(values: monitor.trends.cpu, color: colorForUsage(monitor.cpuUsage))
    }

    private var gpuTrend: SparklineSeries {
        SparklineSeries(values: monitor.trends.gpu, color: colorForUsage(monitor.gpuUsage ?? 0))
    }

    private var memoryTrend: SparklineSeries {
        SparklineSeries(values: monitor.trends.memory, color: colorForUsage(monitor.memoryUsage))
    }

    private var loadTrend: SparklineSeries {
        SparklineSeries(values: monitor.trends.load, color: colorForUsage(loadUsagePercent))
    }

    private func colorForUsage(_ usage: Double) -> Color {
        guard !useFlatColors else { return theme.inkPrimary }
        return theme.colorForUsage(usage)
    }

    // MARK: - Health helpers

    private func gradeText(_ grade: HealthScore.Grade) -> String {
        switch grade {
        case .excellent: return "health.grade.excellent".localized
        case .good: return "health.grade.good".localized
        case .fair: return "health.grade.fair".localized
        case .poor: return "health.grade.poor".localized
        case .critical: return "health.grade.critical".localized
        }
    }

    private func gradeColor(_ grade: HealthScore.Grade) -> Color {
        switch grade {
        case .excellent: return theme.signalGood
        case .good: return theme.signalGood.opacity(0.85)
        case .fair: return theme.signalWarn
        case .poor: return theme.signalAccent
        case .critical: return theme.signalBad
        }
    }

    private var dimensionLabels: [(HealthScore.Dimension, String)] {
        [
            (.cpu, "health.dimension.cpu".localized),
            (.memory, "health.dimension.memory".localized),
            (.load, "health.dimension.load".localized),
            (.temperature, "health.dimension.temperature".localized),
            (.gpu, "health.dimension.gpu".localized),
            (.battery, "health.dimension.battery".localized),
            (.diskIO, "health.dimension.diskIO".localized)
        ]
    }

    private var healthSummary: Text {
        var result = Text(verbatim: "")
        var isFirst = true
        for (dimension, label) in dimensionLabels {
            guard let score = monitor.health.breakdown[dimension.rawValue] else { continue }
            if !isFirst {
                // swiftlint:disable:next shorthand_operator
                result = result + Text(verbatim: " · ")
                    .font(.system(size: 22, weight: .bold))
                    .baselineOffset(-4)
                    .foregroundStyle(theme.inkMuted.opacity(0.25))
            }
            isFirst = false
            if settings.useColorIndicator {
                // swiftlint:disable:next shorthand_operator
                result = result + Text(verbatim: label).foregroundColor(levelColor(score: score))
            } else {
                result = result + Text(verbatim: label + " ") + Text(levelText(for: dimension, score: score))
            }
        }
        return result
    }

    private func levelColor(score: Double) -> Color {
        if score >= 85 { return theme.signalGood }
        if score >= 60 { return theme.signalWarn }
        return theme.signalBad
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

    // MARK: - Battery helpers

    private func batteryIcon(_ battery: BatteryInfo) -> String {
        switch battery.state {
        case .charging, .charged: return "battery.100.bolt"
        case .noBattery: return "battery.0"
        case .acNotCharging, .discharging:
            if battery.percent <= 20 { return "battery.25" }
            if battery.percent <= 60 { return "battery.50" }
            return "battery.100"
        }
    }

    private func batteryColor(_ battery: BatteryInfo) -> Color {
        guard !useFlatColors else { return theme.inkPrimary }
        if battery.state == .charging || battery.state == .charged { return theme.signalGood }
        if battery.percent < 20 { return theme.signalBad }
        if battery.percent < 40 { return theme.signalWarn }
        return theme.signalGood
    }

    private func batteryStateText(_ battery: BatteryInfo) -> String {
        switch battery.state {
        case .charging: return "battery.state.charging".localized
        case .discharging: return "battery.state.discharging".localized
        case .charged: return "battery.state.charged".localized
        case .acNotCharging: return "battery.state.acNotCharging".localized
        case .noBattery: return ""
        }
    }

    private func batteryTimeText(_ battery: BatteryInfo) -> String? {
        guard battery.state != .charged, battery.state != .acNotCharging,
              let minutes = battery.timeRemaining, minutes > 0 else {
            return nil
        }
        let hours = minutes / 60
        let mins = minutes % 60
        let hm = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        let key = battery.state == .charging ? "battery.timeToFull" : "battery.timeLeft"
        return String(format: key.localized, hm)
    }

    // MARK: - Network helpers

    private var exitDisplayText: String {
        if let exit = monitor.exitNode {
            return exitText(exit)
        }
        return "network.exit.failed".localized
    }

    private func proxyText(_ proxy: ProxyConfig) -> String {
        guard proxy.isEnabled else { return "network.proxy.none".localized }
        switch proxy.kind {
        case .http:
            return "HTTP \(proxy.host ?? "")"
        case .https:
            return "HTTPS \(proxy.host ?? "")"
        case .socks:
            return "SOCKS \(proxy.host ?? "")"
        case .pac:
            return "PAC"
        case .tun:
            return "TUN \(proxy.host ?? "")"
        case .none:
            return "network.proxy.none".localized
        }
    }

    private func exitText(_ exit: ExitNode) -> String {
        var parts: [String] = [exit.ip]
        let locality = [exit.city, exit.country].compactMap { $0 }.joined(separator: ", ")
        if !locality.isEmpty { parts.append(locality) }
        if let asn = exit.asn { parts.append(asn) }
        return parts.joined(separator: " · ")
    }

    private func formatMBs(_ mbs: Double) -> String {
        String(format: "%.1f MB/s", mbs)
    }

    // MARK: - Cores

    private struct CoreInfo {
        let index: Int
        let displayIndex: Int
        let usage: Double
        let type: CoreType
    }

    private func getSortedCores() -> [CoreInfo] {
        let usages = monitor.coreUsages
        let topology = monitor.coreTopology
        let pCount = topology.performanceCores
        let eCount = topology.efficiencyCores

        if pCount > 0 || eCount > 0 {
            var result: [CoreInfo] = []
            for index in 0..<min(pCount, usages.count) {
                result.append(CoreInfo(index: index, displayIndex: index, usage: usages[index], type: .performance))
            }
            for index in 0..<min(eCount, usages.count - pCount) {
                let actualIndex = pCount + index
                if actualIndex < usages.count {
                    result.append(CoreInfo(
                        index: actualIndex,
                        displayIndex: index,
                        usage: usages[actualIndex],
                        type: .efficiency
                    ))
                }
            }
            return result
        }
        return usages.enumerated().map { index, usage in
            CoreInfo(index: index, displayIndex: index, usage: usage, type: .unknown)
        }
    }

    private func openAbout() {
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .showAbout, object: nil)
        }
    }

    private func closePanel() {
        (NSApp.delegate as? AppDelegate)?.closePanel()
    }
}

// MARK: - Shared rows

private struct ActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    var foregroundColor: Color

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(foregroundColor)
                Spacer()
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SubStat: View {
    @Environment(\.theme) private var theme

    let label: String
    let value: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(value ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.inkPrimary)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(theme.inkFaint)
        }
    }
}

private struct ProcessRow: View {
    @Environment(\.theme) private var theme

    let process: TopProcess
    let useFlatColors: Bool

    var color: Color {
        guard !useFlatColors else { return theme.inkPrimary }
        if process.cpuPercent < 30 {
            return theme.signalGood
        } else if process.cpuPercent < 70 {
            return theme.signalWarn
        } else {
            return theme.signalBad
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(process.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.inkPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    let threshold = Double(index + 1) * 20
                    Rectangle()
                        .fill(process.cpuPercent >= threshold - 10 ? color : theme.wellFill)
                        .frame(width: 7, height: 9)
                        .cornerRadius(1)
                }
            }

            Text(process.cpuDisplayString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
