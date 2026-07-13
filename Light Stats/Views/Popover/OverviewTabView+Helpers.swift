//
//  OverviewTabView+Helpers.swift
//  Light Stats
//

import SwiftUI

extension OverviewTabView {
    var actionRows: some View {
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

    func systemMetricColumn<Top: View, Bottom: View>(
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

    func systemIconValue(icon: String, text: String) -> some View {
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

    func systemSVGIconValue(svgIcon: AppSVGIcon, text: String) -> some View {
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

    var coresSection: some View {
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

    func metricPercent(_ usage: Double) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(String(format: "%.0f", usage))
                .font(.system(size: 16, weight: useFlatColors ? .regular : .bold, design: .rounded))
            Text("%")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.inkMuted)
        }
        .foregroundStyle(useFlatColors ? theme.inkPrimary : colorForUsage(usage))
    }

    var useFlatColors: Bool { settings.useFlatColors }

    var loadUsagePercent: Double {
        let coreCount = monitor.coreTopology.totalCores > 0
            ? monitor.coreTopology.totalCores
            : max(monitor.coreUsages.count, 1)
        return min(100, max(0, monitor.loadAverage.load1 / Double(coreCount) * 100))
    }

    var cpuTrend: SparklineSeries {
        SparklineSeries(values: monitor.trends.cpu, color: colorForUsage(monitor.cpuUsage))
    }

    var gpuTrend: SparklineSeries {
        SparklineSeries(values: monitor.trends.gpu, color: colorForUsage(monitor.gpuUsage ?? 0))
    }

    var memoryTrend: SparklineSeries {
        SparklineSeries(values: monitor.trends.memory, color: colorForUsage(monitor.memoryUsage))
    }

    var loadTrend: SparklineSeries {
        SparklineSeries(values: monitor.trends.load, color: colorForUsage(loadUsagePercent))
    }

    func colorForUsage(_ usage: Double) -> Color {
        guard !useFlatColors else { return theme.inkPrimary }
        return theme.colorForUsage(usage)
    }

    func gradeText(_ grade: HealthScore.Grade) -> String {
        switch grade {
        case .excellent: return "health.grade.excellent".localized
        case .good: return "health.grade.good".localized
        case .fair: return "health.grade.fair".localized
        case .poor: return "health.grade.poor".localized
        case .critical: return "health.grade.critical".localized
        }
    }

    func gradeColor(_ grade: HealthScore.Grade) -> Color {
        switch grade {
        case .excellent: return theme.signalGood
        case .good: return theme.signalGood.opacity(0.85)
        case .fair: return theme.signalWarn
        case .poor: return theme.signalAccent
        case .critical: return theme.signalBad
        }
    }

    var dimensionLabels: [(HealthScore.Dimension, String)] {
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

    var healthSummary: Text {
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

    func levelColor(score: Double) -> Color {
        if score >= 85 { return theme.signalGood }
        if score >= 60 { return theme.signalWarn }
        return theme.signalBad
    }

    func levelText(for dimension: HealthScore.Dimension, score: Double) -> String {
        if dimension == .temperature {
            if score >= 85 { return "health.level.normal".localized }
            if score >= 60 { return "health.level.warm".localized }
            return "health.level.hot".localized
        }
        if score >= 85 { return "health.level.low".localized }
        if score >= 60 { return "health.level.medium".localized }
        return "health.level.high".localized
    }

    func batteryIcon(_ battery: BatteryInfo) -> String {
        switch battery.state {
        case .charging, .charged: return "battery.100.bolt"
        case .noBattery: return "battery.0"
        case .acNotCharging, .discharging:
            if battery.percent <= 20 { return "battery.25" }
            if battery.percent <= 60 { return "battery.50" }
            return "battery.100"
        }
    }

    func batteryColor(_ battery: BatteryInfo) -> Color {
        guard !useFlatColors else { return theme.inkPrimary }
        if battery.state == .charging || battery.state == .charged { return theme.signalGood }
        if battery.percent < 20 { return theme.signalBad }
        if battery.percent < 40 { return theme.signalWarn }
        return theme.signalGood
    }

    func batteryStateText(_ battery: BatteryInfo) -> String {
        switch battery.state {
        case .charging: return "battery.state.charging".localized
        case .discharging: return "battery.state.discharging".localized
        case .charged: return "battery.state.charged".localized
        case .acNotCharging: return "battery.state.acNotCharging".localized
        case .noBattery: return ""
        }
    }

    func batteryTimeText(_ battery: BatteryInfo) -> String? {
        guard battery.state != .charged, battery.state != .acNotCharging,
              let minutes = battery.timeRemaining, minutes > 0 else {
            return nil
        }
        let hours = minutes / 60
        let mins = minutes % 60
        let hourMinute = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        let key = battery.state == .charging ? "battery.timeToFull" : "battery.timeLeft"
        return String(format: key.localized, hourMinute)
    }

    var exitDisplayText: String {
        guard let exit = monitor.exitNode else { return "network.exit.failed".localized }
        return exitText(exit)
    }

    func proxyText(_ proxy: ProxyConfig) -> String {
        guard proxy.isEnabled else { return "network.proxy.none".localized }
        switch proxy.kind {
        case .http: return "HTTP \(proxy.host ?? "")"
        case .https: return "HTTPS \(proxy.host ?? "")"
        case .socks: return "SOCKS \(proxy.host ?? "")"
        case .pac: return "PAC"
        case .tun: return "TUN \(proxy.host ?? "")"
        case .none: return "network.proxy.none".localized
        }
    }

    func exitText(_ exit: ExitNode) -> String {
        var parts: [String] = [exit.ip]
        let locality = [exit.city, exit.country].compactMap { $0 }.joined(separator: ", ")
        if !locality.isEmpty { parts.append(locality) }
        if let asn = exit.asn { parts.append(asn) }
        return parts.joined(separator: " · ")
    }

    func formatMBs(_ mbs: Double) -> String {
        String(format: "%.1f MB/s", mbs)
    }

    struct CoreInfo {
        let index: Int
        let displayIndex: Int
        let usage: Double
        let type: CoreType
    }

    func getSortedCores() -> [CoreInfo] {
        let usages = monitor.coreUsages
        let topology = monitor.coreTopology
        let performanceCount = topology.performanceCores
        let efficiencyCount = topology.efficiencyCores

        if performanceCount > 0 || efficiencyCount > 0 {
            var result: [CoreInfo] = []
            for index in 0..<min(performanceCount, usages.count) {
                result.append(CoreInfo(index: index, displayIndex: index, usage: usages[index], type: .performance))
            }
            for index in 0..<min(efficiencyCount, usages.count - performanceCount) {
                let actualIndex = performanceCount + index
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

    func openAbout() {
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .showAbout, object: nil)
        }
    }

    func closePanel() {
        (NSApp.delegate as? AppDelegate)?.closePanel()
    }
}
