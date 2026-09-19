//
//  BatteryHealthReportTests.swift
//  LightStatsTests
//
//  健康度有两个口径，必须各自读出来，不能拿一个凑另一个：
//  - 本机值：电池控制器上报的最大容量 ÷ 设计容量（`PowerService.healthPercent`）；
//  - 系统值：电源管理报告的最大容量，只在 `system_profiler -json SPPowerDataType` 里公开。
//  本机实测两个数确实不同（80% vs 84%），所以系统值走解析，不走公式。
//

import Foundation
import XCTest
@testable import Light_Stats

final class BatteryHealthReportTests: XCTestCase {

    /// system_profiler 的真实输出形状（只保留健康度这一段）。
    private func profilerReport(maximumCapacity: Any) -> Data {
        let report: [String: Any] = [
            "SPPowerDataType": [
                [
                    "sppower_battery_health_info": [
                        "sppower_battery_cycle_count": 833,
                        "sppower_battery_health": "Good",
                        "sppower_battery_health_maximum_capacity": maximumCapacity
                    ]
                ]
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: report)) ?? Data()
    }

    // 产品规则：系统报告的 "84%" 必须读成 84。
    func testReadsSystemReportedMaximumCapacity() {
        XCTAssertEqual(PowerService.systemHealthPercent(fromProfilerJSON: profilerReport(maximumCapacity: "84%")), 84)
    }

    // 有的系统版本把容量写成数字而不是带百分号的字符串，同样要读出来。
    func testReadsNumericCapacity() {
        XCTAssertEqual(PowerService.systemHealthPercent(fromProfilerJSON: profilerReport(maximumCapacity: 84)), 84)
    }

    // 两个口径都存在时各自成立：本机容量比 80%，系统报告 84%，互不覆盖。
    func testMeasuredAndSystemHealthStayIndependent() {
        let merged = PowerService.mergedBatteryLayers([
            PowerService.BatteryLayer(origin: "AppleSmartBatteryPack.BatteryData", values: [
                "DesignCapacity": NSNumber(value: 6_075),
                "AppleRawMaxCapacity": NSNumber(value: 4_835)
            ])
        ])

        XCTAssertEqual(PowerService.healthPercent(from: merged.values), 80)
        XCTAssertEqual(PowerService.systemHealthPercent(fromProfilerJSON: profilerReport(maximumCapacity: "84%")), 84)
    }

    // 换新电池后系统会短暂报 >100%，按 100 截断，不能显示成三位数。
    func testOverOneHundredIsClamped() {
        XCTAssertEqual(PowerService.systemHealthPercent(fromProfilerJSON: profilerReport(maximumCapacity: "105%")), 100)
    }

    // 系统没给这个键时保持取不到，而不是编一个数。
    func testMissingHealthInfoStaysUnavailable() {
        let report: [String: Any] = ["SPPowerDataType": [["sppower_battery_cycle_count": 833]]]
        let data = (try? JSONSerialization.data(withJSONObject: report)) ?? Data()

        XCTAssertNil(PowerService.systemHealthPercent(fromProfilerJSON: data))
    }

    // 非数字（占位符、破折号）不算健康度。
    func testNonNumericValueStaysUnavailable() {
        XCTAssertNil(PowerService.systemHealthPercent(fromProfilerJSON: profilerReport(maximumCapacity: "—")))
        XCTAssertNil(PowerService.systemHealthPercent(fromProfilerJSON: profilerReport(maximumCapacity: "0%")))
    }

    // 输出被截断、进程写坏了 stdout 时不能崩。
    func testMalformedOutputStaysUnavailable() {
        XCTAssertNil(PowerService.systemHealthPercent(fromProfilerJSON: Data("not json".utf8)))
        XCTAssertNil(PowerService.systemHealthPercent(fromProfilerJSON: Data()))
    }
}
