nonisolated struct BatteryChargeControlSnapshot: Sendable, Equatable {
    var status: BatteryChargeControlStatus
    var backend: BatteryChargeControlBackend
    var percent: Int?
    var upperLimit: Int
    var lowerLimit: Int
    var helperAvailable: Bool
    var errorMessage: String?

    static let inactive = BatteryChargeControlSnapshot(
        status: .disabled,
        backend: .unknown,
        percent: nil,
        upperLimit: 80,
        lowerLimit: 75,
        helperAvailable: false,
        errorMessage: nil
    )
}
