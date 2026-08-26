import Foundation

enum BatteryControlIPC {
    static let daemonPlistName = "cain.com.light-stats.battery-helper.plist"
    static let machServiceName = "cain.com.light-stats.battery-helper"
    static let helperBundleIdentifier = "cain.com.light-stats.battery-helper"
    static let clientBundleIdentifier = "cain.com.light-stats"
    static let clientCodeSigningRequirement =
        "identifier \"cain.com.light-stats\" and anchor apple generic " +
        "and certificate leaf[subject.OU] = \"QZZ878S3NS\""
    static let helperCodeSigningRequirement =
        "identifier \"cain.com.light-stats.battery-helper\" and anchor apple generic " +
        "and certificate leaf[subject.OU] = \"QZZ878S3NS\""
}

enum BatteryControlStatusCode: Int {
    case unavailable = 0
    case disabled = 1
    case charging = 2
    case holding = 3
    case discharging = 4
    case error = 5
}

enum BatteryControlBackendCode: Int {
    case unknown = 0
    case legacy = 1
    case firmware = 2
}

@objc protocol BatteryControlHelperProtocol {
    func configure(
        enabled: Bool,
        upperLimit: Int,
        lowerLimit: Int,
        revision: Int64,
        withReply reply: @escaping (Bool, String?) -> Void
    )

    func status(
        withReply reply: @escaping (Int, Int, Int, Int, Int, Bool, String?) -> Void
    )

    func reset(revision: Int64, withReply reply: @escaping (Bool, String?) -> Void)
}
