//
//  DisplayIdentity.swift
//  Light Stats
//

import Foundation

nonisolated enum DisplayIdentity {
    static func storageID(vendorID: UInt32, modelID: UInt32, serialNumber: UInt32) -> String {
        String(format: "display.%08X.%08X.%08X", vendorID, modelID, serialNumber)
    }
}
