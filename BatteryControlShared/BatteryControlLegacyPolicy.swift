import Foundation

enum BatteryControlLegacyPolicy {
    static func shouldHoldChargingBeforeSleep(enabled: Bool, upperLimit: Int) -> Bool {
        enabled && upperLimit < BatteryControlLimits.maximumUpper
    }

    static func shouldEnableCharging(
        percent: Int,
        upperLimit: Int,
        lowerLimit: Int,
        currentlyEnabled: Bool
    ) -> Bool {
        if percent >= upperLimit {
            return false
        }
        if percent < lowerLimit {
            return true
        }
        return currentlyEnabled
    }
}
