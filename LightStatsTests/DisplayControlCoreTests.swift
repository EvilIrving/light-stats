//
//  DisplayControlCoreTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

final class DisplayControlCoreTests: XCTestCase {
    func testReadRequestPacketAndChecksum() {
        XCTAssertEqual(
            DDCPacketCodec.readRequest(vcpCode: DDCVCPCode.luminance.rawValue),
            [0x82, 0x01, 0x10, 0xFD]
        )
    }

    func testWriteRequestPacketAndChecksum() {
        XCTAssertEqual(
            DDCPacketCodec.writeRequest(vcpCode: DDCVCPCode.luminance.rawValue, value: 50),
            [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A]
        )
    }

    func testReplyParsingPreservesExplicitUnsupportedResult() {
        let reply = makeReply(resultCode: 0x01, code: 0x10, maximum: 100, current: 40)
        let parsed = DDCPacketCodec.parseReply(reply, expectedVCPCode: 0x10)

        XCTAssertEqual(parsed?.resultCode, 0x01)
        XCTAssertEqual(parsed?.maximum, 100)
        XCTAssertEqual(parsed?.current, 40)
    }

    func testReplyParsingRejectsCorruptChecksumAndWrongVCP() {
        var corrupt = makeReply(resultCode: 0, code: 0x10, maximum: 255, current: 128)
        corrupt[9] ^= 0x01

        XCTAssertNil(DDCPacketCodec.parseReply(corrupt, expectedVCPCode: 0x10))
        XCTAssertNil(
            DDCPacketCodec.parseReply(
                makeReply(resultCode: 0, code: 0x13, maximum: 100, current: 50),
                expectedVCPCode: 0x10
            )
        )
    }

    func testRawPercentConversionClampsAndScales() {
        XCTAssertEqual(DDCRawConversion.rawValue(percent: -5, maximum: 100), 0)
        XCTAssertEqual(DDCRawConversion.rawValue(percent: 150, maximum: 100), 100)
        XCTAssertEqual(DDCRawConversion.rawValue(percent: 50, maximum: 255), 128)
        XCTAssertEqual(DDCRawConversion.percent(rawValue: 128, maximum: 255), 50.196, accuracy: 0.01)
        XCTAssertEqual(DDCRawConversion.percent(rawValue: 200, maximum: 100), 100, accuracy: 0.001)
        XCTAssertEqual(DDCRawConversion.sanitizedMaximum(0), 1)
        XCTAssertEqual(DDCRawConversion.sanitizedMaximum(.max), 32_767)
    }

    func testCapabilityCacheDefaultsToUnknownAndOnlyStoresExplicitState() {
        let cache = DDCCapabilityCache()
        XCTAssertEqual(cache.entry(for: 1).capability, .unknown)

        cache.setUnsupported(displayID: 1)
        XCTAssertEqual(cache.entry(for: 1).capability, .unsupported)

        cache.setUnknown(displayID: 1)
        XCTAssertEqual(cache.entry(for: 1).capability, .unknown)

        cache.setSupported(displayID: 1, code: .legacyBacklight, maximum: 0)
        XCTAssertEqual(cache.entry(for: 1).capability, .supported)
        XCTAssertEqual(cache.entry(for: 1).code, .legacyBacklight)
        XCTAssertEqual(cache.entry(for: 1).maximum, 1)
    }

    func testCapabilityCacheRetainsOnlyOnlineDisplays() {
        let cache = DDCCapabilityCache()
        cache.setUnsupported(displayID: 1)
        cache.setSupported(displayID: 2, code: .luminance, maximum: 100)
        cache.retain(displayIDs: [2])

        XCTAssertEqual(cache.entry(for: 1).capability, .unknown)
        XCTAssertEqual(cache.entry(for: 2).capability, .supported)
    }

    func testStableStorageIDUsesOnlyHardwareIdentity() {
        let storageID = DisplayIdentity.storageID(
            vendorID: 0x10AC,
            modelID: 0x436A,
            serialNumber: 0x4242394C
        )

        XCTAssertEqual(storageID, "display.000010AC.0000436A.4242394C")
    }

    func testControlledDisplayCarriesNameRoleAndStableIdentity() {
        let display = ControlledDisplay(
            id: 2,
            storageID: "display.000010AC.0000436A.4242394C",
            displayName: "DELL U2725QE",
            backend: .ddc,
            isBuiltIn: false,
            capability: .supported,
            brightness: 81
        )

        XCTAssertEqual(display.displayName, "DELL U2725QE")
        XCTAssertFalse(display.isBuiltIn)
        XCTAssertEqual(display.storageID, "display.000010AC.0000436A.4242394C")

        let builtIn = ControlledDisplay(
            id: 1,
            storageID: "display.00000610.0000A04E.FD626D62",
            displayName: "MacBook Pro",
            backend: .native,
            isBuiltIn: true,
            capability: .supported,
            brightness: 53
        )
        XCTAssertEqual(builtIn.displayName, "MacBook Pro")
        XCTAssertTrue(builtIn.isBuiltIn)
    }

    func testDisplayMatchScorePrioritizesLocationAndIdentity() {
        let display = DisplayMatchScorer.DisplayDescriptor(
            location: "IOService:/display-1",
            productName: "Studio Display",
            serialNumber: 42,
            edidFragments: [0: "0610", 4: "1234"]
        )
        let exact = DisplayMatchScorer.ServiceDescriptor(
            location: "IOService:/display-1",
            productName: "studio display",
            serialNumber: 42,
            edidUUID: "06101234"
        )
        let nameOnly = DisplayMatchScorer.ServiceDescriptor(
            location: "IOService:/display-2",
            productName: "Studio Display",
            serialNumber: 0,
            edidUUID: "00000000"
        )

        XCTAssertEqual(DisplayMatchScorer.score(display: display, service: exact), 17)
        XCTAssertEqual(DisplayMatchScorer.score(display: display, service: nameOnly), 2)
    }

    func testHardwareAdjustableRequiresSupportedCapability() {
        let supported = ControlledDisplay(
            id: 2,
            storageID: "display.000010AC.0000436A.4242394C",
            displayName: "DELL U2725QE",
            backend: .ddc,
            isBuiltIn: false,
            capability: .supported,
            brightness: 81
        )
        let unknown = ControlledDisplay(
            id: 3,
            storageID: "display.000010AC.000041AC.41595A57",
            displayName: "DELL U2719DS",
            backend: .ddc,
            isBuiltIn: false,
            capability: .unknown,
            brightness: 73
        )
        let unsupported = ControlledDisplay(
            id: 4,
            storageID: "display.000010AC.000041AC.41595A57",
            displayName: "DELL U2719DS",
            backend: .ddc,
            isBuiltIn: false,
            capability: .unsupported,
            brightness: 73
        )

        XCTAssertTrue(supported.isHardwareAdjustable)
        XCTAssertFalse(unknown.isHardwareAdjustable)
        XCTAssertFalse(unsupported.isHardwareAdjustable)
    }

    private func makeReply(
        resultCode: UInt8,
        code: UInt8,
        maximum: UInt16,
        current: UInt16
    ) -> [UInt8] {
        var bytes: [UInt8] = [
            0x6E, 0x88, 0x02, resultCode, code, 0,
            UInt8(maximum >> 8), UInt8(maximum & 0xFF),
            UInt8(current >> 8), UInt8(current & 0xFF)
        ]
        bytes.append(DDCPacketCodec.checksum(seed: 0x50, bytes: bytes[...]))
        return bytes
    }
}
