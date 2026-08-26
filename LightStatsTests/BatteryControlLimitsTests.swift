import XCTest
@testable import Light_Stats

final class BatteryControlLimitsTests: XCTestCase {
    func testDefaultRangeIsValid() {
        XCTAssertTrue(
            BatteryControlLimits.isValid(
                upper: BatteryControlLimits.defaultUpper,
                lower: BatteryControlLimits.defaultLower
            )
        )
        XCTAssertEqual(BatteryControlLimits.defaultUpper, 80)
        XCTAssertEqual(BatteryControlLimits.defaultLower, 75)
    }

    func testRejectsLowerBoundAndGapViolations() {
        XCTAssertFalse(BatteryControlLimits.isValid(upper: 80, lower: 19))
        XCTAssertFalse(BatteryControlLimits.isValid(upper: 24, lower: 20))
        XCTAssertFalse(BatteryControlLimits.isValid(upper: 101, lower: 80))
        XCTAssertFalse(BatteryControlLimits.isValid(upper: 80, lower: 80))
    }

    func testAcceptsMinimumLegalRange() {
        XCTAssertTrue(BatteryControlLimits.isValid(upper: 25, lower: 20))
        XCTAssertTrue(BatteryControlLimits.isValid(upper: 100, lower: 95))
    }

    func testClampBringsInvalidPairsOntoPolicy() {
        assertClamped(upper: 0, lower: 0, expectedUpper: 25, expectedLower: 20)
        assertClamped(upper: 10, lower: 90, expectedUpper: 25, expectedLower: 20)
        assertClamped(upper: 80, lower: 90, expectedUpper: 80, expectedLower: 75)
        assertClamped(upper: 150, lower: 5, expectedUpper: 100, expectedLower: 20)
        assertClamped(upper: 80, lower: 75, expectedUpper: 80, expectedLower: 75)
    }

    func testLittleEndianFirmwareLimitEncoding() {
        XCTAssertEqual(BatteryControlSMCEncoding.littleEndianBytes(from: 80), [80, 0, 0, 0])
        XCTAssertEqual(BatteryControlSMCEncoding.littleEndianBytes(from: 256), [0, 1, 0, 0])
        XCTAssertEqual(BatteryControlSMCEncoding.littleEndianUInt32(from: [80, 0, 0, 0]), 80)
        XCTAssertEqual(BatteryControlSMCEncoding.littleEndianUInt32(from: [0, 1, 0, 0]), 256)
        XCTAssertNil(BatteryControlSMCEncoding.littleEndianUInt32(from: [1, 2, 3]))
    }

    func testLegacyPolicyChargesBelowLowerLimit() {
        XCTAssertTrue(
            BatteryControlLegacyPolicy.shouldEnableCharging(
                percent: 30,
                upperLimit: 80,
                lowerLimit: 75,
                currentlyEnabled: false
            )
        )
    }

    func testLegacyPolicyHoldsAtUpperLimit() {
        XCTAssertFalse(
            BatteryControlLegacyPolicy.shouldEnableCharging(
                percent: 80,
                upperLimit: 80,
                lowerLimit: 75,
                currentlyEnabled: true
            )
        )
    }

    func testLegacyPolicyPreservesHysteresisStateInsideRange() {
        XCTAssertTrue(
            BatteryControlLegacyPolicy.shouldEnableCharging(
                percent: 77,
                upperLimit: 80,
                lowerLimit: 75,
                currentlyEnabled: true
            )
        )
        XCTAssertFalse(
            BatteryControlLegacyPolicy.shouldEnableCharging(
                percent: 77,
                upperLimit: 80,
                lowerLimit: 75,
                currentlyEnabled: false
            )
        )
    }

    private func assertClamped(
        upper: Int,
        lower: Int,
        expectedUpper: Int,
        expectedLower: Int
    ) {
        let clamped = BatteryControlLimits.clamp(upper: upper, lower: lower)
        XCTAssertEqual(clamped.upper, expectedUpper)
        XCTAssertEqual(clamped.lower, expectedLower)
    }
}
