import XCTest
@testable import Light_Stats

final class MemoryUsagePolicyTests: XCTestCase {
    func testAnonymousMemoryIncludesInactiveAppPagesAndExcludesPurgeablePages() {
        XCTAssertEqual(MemoryUsagePolicy.usedBytes(
            total: 32_000, anonymous: 12_000, purgeable: 2_000, wired: 3_000, compressed: 4_000
        ), 17_000, "Used RAM is non-purgeable anonymous memory plus wired and physical compressor storage")
    }

    func testChangingPageActivityDoesNotChangeApplicationOwnership() {
        // The same anonymous pages moving active -> inactive must not reduce used
        // memory. Active/inactive and file cache are deliberately not inputs.
        let used = MemoryUsagePolicy.usedBytes(total: 32, anonymous: 16, purgeable: 2, wired: 3, compressed: 4)
        XCTAssertEqual(used, 21)
    }

    func testInconsistentCountersDoNotUnderflowOrExceedPhysicalRAM() {
        XCTAssertEqual(MemoryUsagePolicy.usedBytes(total: 32, anonymous: 2, purgeable: 4, wired: 3, compressed: 4), 7)
        XCTAssertEqual(MemoryUsagePolicy.usedBytes(total: 32, anonymous: 30, purgeable: 0, wired: 3, compressed: 4), 32)
        XCTAssertEqual(MemoryUsagePolicy.usedBytes(total: 0, anonymous: 30, purgeable: 0, wired: 3, compressed: 4), 0)
        XCTAssertEqual(MemoryUsagePolicy.usedBytes(
            total: UInt64.max, anonymous: UInt64.max, purgeable: 0, wired: 1, compressed: UInt64.max
        ), UInt64.max)
    }
}
