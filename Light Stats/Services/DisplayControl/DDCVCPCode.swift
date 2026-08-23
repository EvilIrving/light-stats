//
//  DDCVCPCode.swift
//  Light Stats
//

nonisolated enum DDCVCPCode: UInt8, CaseIterable, Sendable {
    case luminance = 0x10
    case legacyBacklight = 0x13

    static let brightnessCandidates: [DDCVCPCode] = [.luminance, .legacyBacklight]
}
