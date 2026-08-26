import Foundation

enum BatteryControlLegacyPolicy {
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
