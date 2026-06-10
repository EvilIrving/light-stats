import SwiftUI

// MARK: - Shared Overview Components
// Used by ClassicOverviewView, DashboardOverviewView, GlassOverviewView, and others.

// MARK: - Health Card

struct HealthCard: View {
    let health: HealthScore
    @Environment(\.appTheme) private var theme

    var body: some View {
        BentoCard(title: "health.title".localized, icon: "heart.text.square") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(health.score)")
                        .font(.system(size: 30, weight: .bold, design: theme.fontDesign))
                        .foregroundColor(gradeColor)
                    Text("/ 100")
                        .font(.system(size: 13, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.secondaryText)
                    Text(gradeText)
                        .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                        .foregroundColor(gradeColor)
                        .padding(.leading, 4)
                    Spacer()
                    Circle()
                        .fill(gradeColor)
                        .frame(width: 10, height: 10)
                }

                Text(summaryText)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.secondaryText)
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
        case .excellent: return theme.success
        case .good: return Color(red: 0.35, green: 0.78, blue: 0.42)
        case .fair: return theme.warning
        case .poor: return .orange
        case .critical: return theme.danger
        }
    }

    private var summaryText: String {
        let dimensions: [(HealthScore.Dimension, String)] = [
            (.cpu, "health.dimension.cpu".localized),
            (.memory, "health.dimension.memory".localized),
            (.disk, "health.dimension.disk".localized),
            (.temperature, "health.dimension.temperature".localized),
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

// MARK: - Battery Card

struct BatteryCard: View {
    let battery: BatteryInfo
    let temperatureUnit: SettingsManager.TemperatureUnit
    @Environment(\.appTheme) private var theme

    var body: some View {
        BentoCard(title: "battery.title".localized, icon: batteryIcon) {
            if battery.state == .noBattery {
                Text("battery.na".localized)
                    .font(.system(size: 20, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", battery.percent))
                            .font(.system(size: 24, weight: .bold, design: theme.fontDesign))
                            .foregroundColor(batteryColor)
                        Text("%")
                            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                            .foregroundColor(theme.secondaryText)
                        Text(stateText)
                            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                            .foregroundColor(theme.secondaryText)
                            .padding(.leading, 4)
                        Spacer()
                        if let time = timeRemainingText {
                            Text(time)
                                .font(.system(size: 11, design: theme.fontDesign))
                                .foregroundColor(theme.secondaryText)
                        }
                    }
                    Divider()
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
        if battery.state == .charging || battery.state == .charged { return theme.success }
        if battery.percent < 10 { return theme.danger }
        if battery.percent < 20 { return theme.warning }
        return theme.success
    }

    private var stateText: String {
        switch battery.state {
        case .charging: return "battery.state.charging".localized
        case .discharging: return "battery.state.discharging".localized
        case .charged: return "battery.state.charged".localized
        case .noBattery: return ""
        }
    }

    private var timeRemainingText: String? {
        guard battery.state != .charged, let minutes = battery.timeRemaining, minutes > 0 else { return nil }
        let h = minutes / 60; let m = minutes % 60
        let hm = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        let key = battery.state == .charging ? "battery.timeToFull" : "battery.timeLeft"
        return String(format: key.localized, hm)
    }
}

// MARK: - Sub Stat

struct SubStat: View {
    let label: String
    let value: String?
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            Text(value ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(theme.secondaryText)
        }
    }
}

// MARK: - Process Row

struct ProcessRow: View {
    let process: TopProcess
    @Environment(\.appTheme) private var theme

    var color: Color {
        if process.cpuPercent < 30 { return theme.success }
        if process.cpuPercent < 70 { return theme.warning }
        return theme.danger
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(process.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let threshold = Double(i + 1) * 20
                    Rectangle()
                        .fill(process.cpuPercent >= threshold - 10 ? color : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 10)
                        .cornerRadius(2)
                }
            }

            Text(process.cpuDisplayString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

// MARK: - Spinning Fan Icon

struct SpinningFanIcon: View {
    let rpm: Int?

    private let maxRevPerSecond: Double = 1.5
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

    private var degreesPerSecond: Double {
        guard let rpm, rpm > 0 else { return 0 }
        let revPerSec = min(Double(rpm) / rpmAtMaxSpeed, 1.0) * maxRevPerSecond
        return revPerSec * 360.0
    }

    private func advance(to now: Date) {
        let dt = now.timeIntervalSince(lastDate)
        lastDate = now
        guard dt > 0, dt < 1 else { return }
        angle = (angle + degreesPerSecond * dt).truncatingRemainder(dividingBy: 360)
    }
}
