import Foundation

enum BatteryControlLimits {
    static let minimumLower = 20
    static let maximumUpper = 100
    static let minimumGap = 5
    static let defaultUpper = 80
    static let defaultLower = 75

    static var minimumUpper: Int { minimumLower + minimumGap }

    static func isValid(upper: Int, lower: Int) -> Bool {
        lower >= minimumLower
            && upper <= maximumUpper
            && lower + minimumGap <= upper
    }

    static func clamp(upper: Int, lower: Int) -> (upper: Int, lower: Int) {
        let safeUpper = min(max(upper, minimumUpper), maximumUpper)
        let safeLower = min(max(lower, minimumLower), safeUpper - minimumGap)
        return (safeUpper, safeLower)
    }
}
