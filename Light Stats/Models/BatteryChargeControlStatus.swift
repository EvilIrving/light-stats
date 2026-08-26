nonisolated enum BatteryChargeControlStatus: Int, Sendable {
    case unavailable = 0
    case disabled = 1
    case charging = 2
    case holding = 3
    case discharging = 4
    case error = 5
}
