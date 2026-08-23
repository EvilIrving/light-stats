//
//  ControlledDisplay.swift
//  Light Stats
//

nonisolated struct ControlledDisplay: Identifiable, Sendable {
    let id: UInt32
    let storageID: String
    let displayName: String?
    let backend: DisplayControlBackend
    let isBuiltIn: Bool
    var capability: DisplayControlCapability
    var brightness: Double
}
