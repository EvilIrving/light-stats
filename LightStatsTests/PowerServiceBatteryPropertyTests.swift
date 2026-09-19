//
//  PowerServiceBatteryPropertyTests.swift
//  LightStatsTests
//
//  电池健康/温度/状态在不同 macOS 版本的不同键布局下都必须读出来。
//  真实机型上的两代布局：
//  - macOS ≤26：DesignCapacity / AppleRawMaxCapacity / Temperature 都在 AppleSmartBattery 顶层；
//  - macOS 27：顶层只剩 CycleCount / MaxCapacity，容量移进嵌套 BatteryData，
//    温度与 PermanentFailureStatus 只在子节点 AppleSmartBatteryPack 的电量计数据里。
//

import Foundation
import XCTest
@testable import Light_Stats

final class PowerServiceBatteryPropertyTests: XCTestCase {

    private typealias Layer = PowerService.BatteryLayer

    /// macOS ≤26 的布局：所有键都在节点顶层。
    private var legacyLayers: [Layer] {
        [Layer(origin: "AppleSmartBattery", values: [
            "CycleCount": NSNumber(value: 831),
            "DesignCapacity": NSNumber(value: 6_075),
            "AppleRawMaxCapacity": NSNumber(value: 4_874),
            "NominalChargeCapacity": NSNumber(value: 5_024),
            "MaxCapacity": NSNumber(value: 100),
            "Temperature": NSNumber(value: 3_579),
            "PermanentFailureStatus": NSNumber(value: 0)
        ])]
    }

    /// macOS 27 的布局：顶层只剩循环次数与百分比容量，其余下沉到嵌套字典与子节点。
    private var currentLayers: [Layer] {
        [
            Layer(origin: "AppleSmartBattery", values: [
                "CycleCount": NSNumber(value: 831),
                "MaxCapacity": NSNumber(value: 100),
                "BatteryData": [
                    "DesignCapacity": NSNumber(value: 6_075),
                    "NominalChargeCapacity": NSNumber(value: 5_024)
                ]
            ]),
            Layer(origin: "AppleSmartBattery.BatteryData", values: [
                "DesignCapacity": NSNumber(value: 6_075),
                "NominalChargeCapacity": NSNumber(value: 5_024),
                "MaxCapacity": NSNumber(value: 100)
            ]),
            Layer(origin: "AppleSmartBatteryPack", values: ["BankCount": NSNumber(value: 3)]),
            Layer(origin: "AppleSmartBatteryPack.BatteryData", values: [
                "DesignCapacity": NSNumber(value: 6_075),
                "AppleRawMaxCapacity": NSNumber(value: 4_874),
                "Temperature": NSNumber(value: 3_579),
                "PermanentFailureStatus": NSNumber(value: 0)
            ])
        ]
    }

    // 产品规则：macOS 27 把容量与温度下沉到嵌套/子节点键后，健康度与电池温度仍必须显示。
    func testCurrentLayoutRestoresHealthAndTemperature() {
        let merged = PowerService.mergedBatteryLayers(currentLayers)

        XCTAssertEqual(PowerService.healthPercent(from: merged.values), 80)
        XCTAssertEqual(PowerService.batteryTemperatureCelsius(from: merged.values) ?? 0, 35.79, accuracy: 0.001)
        XCTAssertEqual(PowerService.conditionOK(from: merged.values), true)
        XCTAssertEqual(merged.values["CycleCount"] as? Int, 831)
    }

    // 兼容规则：老系统把同一批键放在顶层时，仍从顶层读，结果不变。
    func testLegacyLayoutKeepsReadingTopLevelKeys() {
        let merged = PowerService.mergedBatteryLayers(legacyLayers)

        XCTAssertEqual(PowerService.healthPercent(from: merged.values), 80)
        XCTAssertEqual(PowerService.batteryTemperatureCelsius(from: merged.values) ?? 0, 35.79, accuracy: 0.001)
        XCTAssertEqual(PowerService.conditionOK(from: merged.values), true)
        XCTAssertEqual(merged.origins["DesignCapacity"], "AppleSmartBattery")
        XCTAssertEqual(merged.origins["Temperature"], "AppleSmartBattery")
    }

    // 合并顺序规则：同名键以更靠外的一层为准，嵌套层只是补齐顶层缺失的键。
    func testOutermostLayerWinsForRepeatedKey() {
        let layers = [
            Layer(origin: "AppleSmartBattery", values: ["DesignCapacity": NSNumber(value: 6_000)]),
            Layer(origin: "AppleSmartBattery.BatteryData", values: [
                "DesignCapacity": NSNumber(value: 9_999),
                "AppleRawMaxCapacity": NSNumber(value: 4_874)
            ])
        ]
        let merged = PowerService.mergedBatteryLayers(layers)

        XCTAssertEqual(merged.values["DesignCapacity"] as? Int, 6_000)
        XCTAssertEqual(PowerService.healthPercent(from: merged.values), 81)
    }

    // 键真的缺失时保持 unavailable，而不是拿百分比容量凑一个数。
    func testMissingCapacityKeysStayUnavailable() {
        let layers = [Layer(origin: "AppleSmartBattery", values: [
            "MaxCapacity": NSNumber(value: 100)
        ])]
        let merged = PowerService.mergedBatteryLayers(layers)

        XCTAssertNil(PowerService.healthPercent(from: merged.values))
        XCTAssertNil(PowerService.batteryTemperatureCelsius(from: merged.values))
        XCTAssertNil(PowerService.conditionOK(from: merged.values))
        XCTAssertEqual(PowerService.healthFailureReason(merged.values), "missingDesignCapacity")
        XCTAssertEqual(
            PowerService.batteryTemperatureReason(properties: merged.values, value: nil),
            "missingTemperature"
        )
    }

    // 百分比容量（≤100）不是 mAh 容量，设计容量在场时也不能拿来当最大容量。
    func testPercentCapacityIsNotUsedAsMaximumCapacity() {
        let merged = PowerService.mergedBatteryLayers([Layer(origin: "AppleSmartBattery", values: [
            "DesignCapacity": NSNumber(value: 6_075),
            "MaxCapacity": NSNumber(value: 100)
        ])])

        XCTAssertNil(PowerService.healthPercent(from: merged.values))
    }

    // 脏温度值仍旧丢弃，不显示。
    func testOutOfRangeTemperatureIsDiscarded() {
        XCTAssertNil(PowerService.batteryTemperatureCelsius(from: ["Temperature": NSNumber(value: 9_000)]))
        XCTAssertNil(PowerService.batteryTemperatureCelsius(from: ["Temperature": NSNumber(value: 0)]))
    }

    // 空属性表（服务在、属性读不到）不能崩，也不能给出编造值。
    func testEmptyPropertyTableStaysUnavailable() {
        let merged = PowerService.mergedBatteryLayers([])

        XCTAssertTrue(merged.values.isEmpty)
        XCTAssertNil(PowerService.healthPercent(from: merged.values))
        XCTAssertNil(PowerService.batteryTemperatureCelsius(from: merged.values))
    }
}
