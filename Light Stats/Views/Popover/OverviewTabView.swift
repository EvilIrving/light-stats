//
//  OverviewTabView.swift
//  Light Stats
//
//  Instrument layout: sections + hairlines, driven by `ThemeLayout`.
//

import SwiftUI

struct OverviewTabView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var aiMonitor: AIUsageMonitor
    @Environment(\.theme) var theme
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            instrumentContent
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

    // MARK: - Health

    private var healthSection: some View {
        PanelSection(title: "health.title".localized) {
            VStack(alignment: .leading, spacing: 6) {
                HeroReadout(
                    value: "\(monitor.health.score)",
                    unit: "/ 100",
                    caption: gradeText(monitor.health.grade),
                    valueColor: gradeColor(monitor.health.grade)
                )
                healthSummary
                    .font(theme.chromeStyle.bodyFont)
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
                        .font(
                            useFlatColors
                                ? .system(size: 13, weight: .regular, design: .monospaced)
                                : theme.chromeStyle.metricValueFont
                        )
                        .foregroundStyle(useFlatColors ? theme.inkPrimary : colorForUsage(loadUsagePercent))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                MetricRow(label: "MEM", svgIcon: .memory, trend: memoryTrend) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", Double(monitor.memoryUsed) / 1024 / 1024 / 1024))
                            .font(
                                useFlatColors
                                    ? .system(size: 16, weight: .regular, design: .monospaced)
                                    : theme.chromeStyle.metricValueFont
                            )
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
    private var thermalStrip: some View {
        PanelSection(title: "overview.system".localized) {
            systemMetricsGrid
        }
    }

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
                            .foregroundStyle(theme.metricIcon)
                        Text(formatMBs(monitor.diskIO.readMBs))
                            .foregroundStyle(theme.inkMuted)
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                            .foregroundStyle(theme.metricIcon)
                        Text(formatMBs(monitor.diskIO.writeMBs))
                            .foregroundStyle(theme.inkMuted)
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            )
        }
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
        PanelSection(title: "overview.network".localized) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text(ByteFormatter.formatSpeed(monitor.networkUpload))
                    }
                    .foregroundStyle(theme.chartSecondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text(ByteFormatter.formatSpeed(monitor.networkDownload))
                    }
                    .foregroundStyle(theme.chartLine)
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))

                if monitor.trends.networkUp.count > 1 {
                    Sparkline(series: [
                        SparklineSeries(values: monitor.trends.networkDown, color: theme.chartLine),
                        SparklineSeries(values: monitor.trends.networkUp, color: theme.chartSecondary)
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

}

// MARK: - Shared rows

struct ActionRow: View {
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
                .font(theme.chromeStyle.bodyFont)
                .foregroundStyle(theme.inkPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    let threshold = Double(index + 1) * 20
                    RoundedRectangle(
                        cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 2 : 1
                    )
                    .fill(process.cpuPercent >= threshold - 10 ? color : theme.wellFill)
                    .frame(width: 7, height: 9)
                    .shadow(
                        color: theme.chromeStyle.usesNightBarTreatment
                            && process.cpuPercent >= threshold - 10
                            ? color.opacity(0.55)
                            : .clear,
                        radius: 1.5
                    )
                }
            }

            Text(process.cpuDisplayString)
                .font(theme.chromeStyle.compactValueFont)
                .foregroundStyle(color)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
