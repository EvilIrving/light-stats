//
//  NativeBrightnessService.swift
//  Light Stats
//

import CoreGraphics
import Foundation

nonisolated final class NativeBrightnessService: Sendable {
    func brightness(displayID: CGDirectDisplayID) -> Double? {
        var value: Float = -1
        guard DisplayServicesGetBrightness(displayID, &value) == 0, value >= 0 else {
            return nil
        }
        return Double(min(1, max(0, value))) * 100
    }

    func setBrightness(_ percent: Double, displayID: CGDirectDisplayID) -> Bool {
        let value = Float(min(100, max(0, percent)) / 100)
        return DisplayServicesSetBrightness(displayID, value) == 0
    }
}
