//
//  DisplayControlService.swift
//  Light Stats
//

import AppKit
import CoreGraphics
import Foundation
import IOKit

actor DisplayControlService {
    private let logger = AppLogger(category: "DisplayControl")
    private let nativeBrightness = NativeBrightnessService()
    private let ddcController: DDCController
    private let deviceDisplayNameResolver: DeviceDisplayNameResolver
    private let defaults: UserDefaults
    private var displaysByID: [UInt32: ControlledDisplay] = [:]

    init(
        gate: DDCEnvironmentGate,
        defaults: UserDefaults = .standard,
        deviceDisplayNameResolver: DeviceDisplayNameResolver = DeviceDisplayNameResolver()
    ) {
        ddcController = DDCController(gate: gate)
        self.defaults = defaults
        self.deviceDisplayNameResolver = deviceDisplayNameResolver
    }

    func discoverDisplays() async -> [ControlledDisplay] {
        let displayIDs = onlineDisplayIDs()
        let screenMetadataByID = await Self.screenMetadataByDisplayID()
        await ddcController.refreshRoutes(displayIDs: displayIDs)

        var detected: [ControlledDisplay] = []
        for displayID in displayIDs {
            guard let metadata = metadata(
                displayID: displayID,
                screenMetadata: screenMetadataByID[displayID]
            ), !metadata.shouldIgnore else {
                continue
            }

            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let storageID = DisplayIdentity.storageID(
                vendorID: CGDisplayVendorNumber(displayID),
                modelID: CGDisplayModelNumber(displayID),
                serialNumber: CGDisplaySerialNumber(displayID)
            )
            let fallback = storedBrightness(storageID: storageID) ?? 50

            if let brightness = nativeBrightness.brightness(displayID: displayID) {
                detected.append(
                    ControlledDisplay(
                        id: displayID,
                        storageID: storageID,
                        displayName: metadata.displayName,
                        backend: .native,
                        isBuiltIn: isBuiltIn,
                        capability: .supported,
                        brightness: brightness
                    )
                )
                continue
            }

            guard !isBuiltIn else {
                detected.append(
                    ControlledDisplay(
                        id: displayID,
                        storageID: storageID,
                        displayName: metadata.displayName,
                        backend: .native,
                        isBuiltIn: true,
                        capability: .unsupported,
                        brightness: fallback
                    )
                )
                continue
            }

            let probe = await ddcController.probeBrightness(displayID: displayID)
            detected.append(
                ControlledDisplay(
                    id: displayID,
                    storageID: storageID,
                    displayName: metadata.displayName,
                    backend: .ddc,
                    isBuiltIn: false,
                    capability: probe.capability,
                    brightness: probe.brightness ?? fallback
                )
            )
        }

        detected.sort {
            isOrderedBefore($0, $1, screenMetadataByID: screenMetadataByID)
        }
        displaysByID = Dictionary(uniqueKeysWithValues: detected.map { ($0.id, $0) })
        logger.info("Display discovery completed with \(detected.count) visible displays")
        return detected
    }

    func readBrightness(displayID: UInt32) async -> Double? {
        guard let display = displaysByID[displayID], display.capability != .unsupported else {
            return nil
        }

        switch display.backend {
        case .native:
            return nativeBrightness.brightness(displayID: displayID)
        case .ddc:
            return await ddcController.readBrightness(displayID: displayID)
        }
    }

    func setBrightness(_ percent: Double, displayID: UInt32) async -> Bool {
        guard let display = displaysByID[displayID], display.capability != .unsupported else {
            return false
        }

        let value = min(100, max(0, percent))
        let success: Bool
        switch display.backend {
        case .native:
            success = nativeBrightness.setBrightness(value, displayID: displayID)
        case .ddc:
            success = await ddcController.writeBrightness(value, displayID: displayID)
        }

        if success {
            saveBrightness(value, storageID: display.storageID)
            displaysByID[displayID]?.brightness = value
        }
        return success
    }

    func stop() async {
        displaysByID.removeAll()
        await ddcController.stop()
    }

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else {
            logger.error("CGGetOnlineDisplayList failed")
            return []
        }
        return Array(displays.prefix(Int(count)))
    }

    private func metadata(
        displayID: CGDirectDisplayID,
        screenMetadata: DisplayScreenMetadata?
    ) -> DisplayMetadata? {
        let info = CoreDisplay_DisplayCreateInfoDictionary(displayID) as? [String: Any] ?? [:]
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        let displayName: String?
        if isBuiltIn {
            displayName = deviceDisplayNameResolver.deviceDisplayName()
        } else {
            let coreDisplayName = localizedCoreDisplayName(info: info)
            let screenName = screenMetadata?.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
            displayName = screenName.flatMap { $0.isEmpty ? nil : $0 } ?? coreDisplayName
        }

        let isVirtual = info["kCGDisplayIsVirtualDevice"] as? Bool == true
            || info["kCGDisplayIsAirPlay"] as? Bool == true
        let isDummy = displayName?.localizedCaseInsensitiveContains("dummy") == true
            || info["DisplayVendorID"] as? Int64 == 0xF0F0
        return DisplayMetadata(displayName: displayName, shouldIgnore: isVirtual || isDummy)
    }

    private func localizedCoreDisplayName(info: [String: Any]) -> String? {
        let names = info["DisplayProductName"] as? [String: String] ?? [:]
        return names[Locale.current.identifier]
            ?? names["zh_CN"]
            ?? names["en_US"]
            ?? names.first?.value
    }

    @MainActor
    private static func screenMetadataByDisplayID() -> [UInt32: DisplayScreenMetadata] {
        var result: [UInt32: DisplayScreenMetadata] = [:]
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID else {
                continue
            }
            result[displayID] = DisplayScreenMetadata(
                displayID: displayID,
                localizedName: screen.localizedName,
                minX: screen.frame.minX,
                minY: screen.frame.minY
            )
        }
        return result
    }

    private func isOrderedBefore(
        _ lhs: ControlledDisplay,
        _ rhs: ControlledDisplay,
        screenMetadataByID: [UInt32: DisplayScreenMetadata]
    ) -> Bool {
        if lhs.isBuiltIn != rhs.isBuiltIn {
            return lhs.isBuiltIn
        }

        let lhsScreen = screenMetadataByID[lhs.id]
        let rhsScreen = screenMetadataByID[rhs.id]
        let lhsPosition = (lhsScreen?.minX ?? .greatestFiniteMagnitude, lhsScreen?.minY ?? .greatestFiniteMagnitude)
        let rhsPosition = (rhsScreen?.minX ?? .greatestFiniteMagnitude, rhsScreen?.minY ?? .greatestFiniteMagnitude)
        if lhsPosition.0 != rhsPosition.0 {
            return lhsPosition.0 < rhsPosition.0
        }
        if lhsPosition.1 != rhsPosition.1 {
            return lhsPosition.1 < rhsPosition.1
        }

        let nameComparison = (lhs.displayName ?? "").localizedStandardCompare(rhs.displayName ?? "")
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.storageID < rhs.storageID
    }

    private func storedBrightness(storageID: String) -> Double? {
        let key = brightnessKey(storageID: storageID)
        guard defaults.object(forKey: key) != nil else { return nil }
        return min(100, max(0, defaults.double(forKey: key)))
    }

    private func saveBrightness(_ value: Double, storageID: String) {
        defaults.set(value, forKey: brightnessKey(storageID: storageID))
    }

    private func brightnessKey(storageID: String) -> String {
        "displayControl.brightness.\(storageID)"
    }

    private struct DisplayMetadata {
        let displayName: String?
        let shouldIgnore: Bool
    }
}
