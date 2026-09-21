//
//  SMCInfoFanProbeTests.swift
//  LightStatsTests
//
//  风扇报告要能区分「这台机器没有风扇」和「有风扇但读不到」。这里钉住这个判定，
//  以及转速键的解析口径（0 是有效值）。
//

import Foundation
import XCTest
@testable import Light_Stats

final class SMCInfoFanProbeTests: XCTestCase {

    // 产品规则：没有风扇键 = 无风扇机型（MacBook Air），不是回归。
    func testMissingFanKeysMeansFanlessMachine() {
        XCTAssertEqual(SMCInfo.fanFailureReason(anyFanKeyPresent: false), "noFanKeys")
    }

    // 产品规则：键存在但读不出值 = 可能回归，必须与无风扇分开。
    func testPresentButUnreadableFanKeysMeansRegression() {
        XCTAssertEqual(SMCInfo.fanFailureReason(anyFanKeyPresent: true), "fanKeysUnreadable")
    }

    func testFloatFanBytesParseToRPM() {
        XCTAssertEqual(SMCInfo.parseFanRPM(from: floatBytes(2_500)), 2_500)
        XCTAssertEqual(SMCInfo.parseFanRPM(from: floatBytes(0)), 0, "0 RPM（风扇停转）是有效值")
    }

    func testOutOfRangeFloatIsNotAValue() {
        XCTAssertNil(SMCInfo.parseFanRPM(from: floatBytes(12_000)))
        XCTAssertNil(SMCInfo.parseFanRPM(from: floatBytes(-1)))
    }

    func testFPE2BytesParseToRPM() {
        // FPE2 变体 1：(byte0 << 6) | (byte1 >> 2) = (39 << 6) | (16 >> 2) = 2500
        XCTAssertEqual(SMCInfo.parseFanRPM(from: [39, 16]), 2_500)
    }

    func testShortOrEmptyDataIsNotAValue() {
        XCTAssertNil(SMCInfo.parseFanRPM(from: []))
        XCTAssertNil(SMCInfo.parseFanRPM(from: [0x12]))
    }

    func testEvidenceListsEveryAttemptedKeyWithItsOutcome() {
        let probe = SMCInfo.FanProbe(
            rpm: nil,
            reasonCode: SMCInfo.FanReason.noFanKeys,
            fanCountFromSMC: nil,
            keys: [
                SMCInfo.FanKeyProbe(key: "FNum", outcome: .missing, value: nil),
                SMCInfo.FanKeyProbe(key: "F0Ac", outcome: .value, value: 2_500),
                SMCInfo.FanKeyProbe(key: "F1Ac", outcome: .failed, value: nil)
            ]
        )

        let values = SMCInfo.fanEvidenceValues(probe)

        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(caseObject(values[0])?["key"], .string("FNum"))
        XCTAssertEqual(caseObject(values[0])?["present"], .bool(false))
        XCTAssertEqual(caseObject(values[0])?["outcome"], .string("missing"))
        XCTAssertNil(caseObject(values[0])?["value"], "读不到的键不该凭空带值")
        XCTAssertEqual(caseObject(values[1])?["present"], .bool(true))
        XCTAssertEqual(caseObject(values[1])?["outcome"], .string("value"))
        XCTAssertEqual(caseObject(values[1])?["value"], .integer(2_500))
        XCTAssertEqual(caseObject(values[2])?["outcome"], .string("failed"))
    }

    func testEvidenceFieldsCarryCountAndReconnectFlag() {
        let probe = SMCInfo.FanProbe(
            rpm: 2_500,
            reasonCode: SMCInfo.FanReason.valueRead,
            fanCountFromSMC: 2,
            keys: []
        )

        let fields = SMCInfo.fanEvidenceFields(probe, reconnected: true)

        XCTAssertEqual(fields["fanCount"], .privateValue(.integer(2)))
        XCTAssertEqual(fields["reconnected"], .publicValue("true"))
        XCTAssertEqual(fields["attempts"], .privateValue(.array([])))
    }

    // MARK: - Helpers

    private func floatBytes(_ value: Float) -> [UInt8] {
        var value = value
        return withUnsafeBytes(of: &value) { Array($0) }
    }

    private func caseObject(_ value: DiagnosticLogService.Value) -> [String: DiagnosticLogService.Value]? {
        guard case .object(let object) = value else { return nil }
        return object
    }
}
