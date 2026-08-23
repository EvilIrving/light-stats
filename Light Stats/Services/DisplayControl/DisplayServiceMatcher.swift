//
//  DisplayServiceMatcher.swift
//  Light Stats
//

import CoreGraphics
import Foundation
import IOKit

nonisolated final class DisplayServiceMatcher: Sendable {
    private let logger = AppLogger(category: "DisplayControl")

    func matchedServices(displayIDs: [CGDirectDisplayID]) -> [UInt32: DDCServiceRoute] {
#if arch(arm64)
        let services = registryServices()
        var candidates: [MatchCandidate] = []

        for displayID in displayIDs where CGDisplayIsBuiltin(displayID) == 0 {
            let display = displayDescriptor(displayID: displayID)
            for service in services {
                let score = DisplayMatchScorer.score(display: display, service: service.descriptor)
                guard score > 0, let avService = service.service else { continue }
                candidates.append(
                    MatchCandidate(
                        displayID: displayID,
                        service: avService,
                        serviceLocation: service.serviceLocation,
                        score: score,
                        chipAddress: service.usesMCDP29XXRoute ? 0xB7 : 0x37
                    )
                )
            }
        }

        candidates.sort {
            if $0.score == $1.score {
                return $0.serviceLocation < $1.serviceLocation
            }
            return $0.score > $1.score
        }

        var result: [UInt32: DDCServiceRoute] = [:]
        var usedLocations: Set<Int> = []
        for candidate in candidates where result[candidate.displayID] == nil {
            guard !usedLocations.contains(candidate.serviceLocation) else { continue }
            result[candidate.displayID] = DDCServiceRoute(
                displayID: candidate.displayID,
                service: candidate.service,
                location: candidate.serviceLocation,
                matchScore: candidate.score,
                chipAddress: candidate.chipAddress
            )
            usedLocations.insert(candidate.serviceLocation)
        }

        logger.info("Matched \(result.count) displays to \(services.count) DDC services")
        return result
#else
        _ = displayIDs
        return [:]
#endif
    }

#if arch(arm64)
    private func registryServices() -> [RegistryService] {
        let framebuffers = ["AppleCLCD2", "IOMobileFramebufferShim"]
            .flatMap(framebufferServices(className:))
        guard !framebuffers.isEmpty else { return [] }

        var result: [RegistryService] = []
        var usedFramebufferIndices: Set<Int> = []
        var serviceLocation = 0

        forEachService(matching: "DCPAVServiceProxy") { entry in
            guard property(entry: entry, key: "Location") as? String == "External",
                  let unmanagedService = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)
            else {
                return
            }

            let expectedIndex = dcpIndexForProxy(entry: entry)
            let framebuffer = framebuffers.first {
                $0.dcpIndex == expectedIndex && !usedFramebufferIndices.contains($0.dcpIndex)
            } ?? framebuffers.first {
                !usedFramebufferIndices.contains($0.dcpIndex)
            }
            guard var framebuffer else { return }

            serviceLocation += 1
            usedFramebufferIndices.insert(framebuffer.dcpIndex)
            framebuffer.serviceLocation = serviceLocation
            framebuffer.service = unmanagedService.takeRetainedValue()
            framebuffer.usesMCDP29XXRoute = usesMCDP29XXRoute(entry: entry)
            result.append(framebuffer)
        }
        return result
    }

    private func framebufferServices(className: String) -> [RegistryService] {
        var result: [RegistryService] = []
        forEachService(matching: className) { entry in
            let isExternal = property(entry: entry, key: "external") as? Bool == true
            guard isExternal else { return }
            let display = registryDisplay(entry: entry)
            if !display.productName.isEmpty || !display.edidUUID.isEmpty {
                result.append(display)
            }
        }
        return result
    }

    private func registryDisplay(entry: io_service_t) -> RegistryService {
        var result = RegistryService()
        result.dcpIndex = property(entry: entry, key: "DCPIndex") as? Int ?? -1
        result.edidUUID = property(entry: entry, key: "EDID UUID") as? String ?? ""

        var path = [CChar](repeating: 0, count: 1_024)
        if IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS {
            result.ioDisplayLocation = String(cString: path)
        }

        if let attributes = property(entry: entry, key: "DisplayAttributes") as? [String: Any],
           let product = attributes["ProductAttributes"] as? [String: Any] {
            result.productName = product["ProductName"] as? String ?? ""
            result.serialNumber = product["SerialNumber"] as? Int64 ?? 0
        }
        return result
    }

    private func dcpIndexForProxy(entry: io_service_t) -> Int {
        guard let role = inheritedStringProperty(entry: entry, key: "role"),
              role.hasPrefix("DCPEXT"),
              let externalIndex = Int(role.dropFirst(6))
        else {
            return -1
        }
        return externalIndex + 1
    }

    private func forEachService(matching className: String, body: (io_service_t) -> Void) {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(className),
            &iterator
        ) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            body(entry)
            IOObjectRelease(entry)
        }
    }

    private func displayDescriptor(displayID: CGDirectDisplayID) -> DisplayMatchScorer.DisplayDescriptor {
        guard let info = CoreDisplay_DisplayCreateInfoDictionary(displayID) as? [String: Any]
        else {
            return DisplayMatchScorer.DisplayDescriptor(
                location: "",
                productName: "",
                serialNumber: 0,
                edidFragments: [:]
            )
        }

        let names = info["DisplayProductName"] as? [String: String] ?? [:]
        return DisplayMatchScorer.DisplayDescriptor(
            location: info[kIODisplayLocationKey] as? String ?? "",
            productName: names["en_US"] ?? names.first?.value ?? "",
            serialNumber: info[kDisplaySerialNumber] as? Int64 ?? 0,
            edidFragments: edidFragments(info: info)
        )
    }

    private func edidFragments(info: [String: Any]) -> [Int: String] {
        guard let vendor = info[kDisplayVendorID] as? Int64,
              let product = info[kDisplayProductID] as? Int64,
              let week = info[kDisplayWeekOfManufacture] as? Int64,
              let year = info[kDisplayYearOfManufacture] as? Int64,
              let horizontalSize = info[kDisplayHorizontalImageSize] as? Int64,
              let verticalSize = info[kDisplayVerticalImageSize] as? Int64
        else {
            return [:]
        }

        let safeProduct = UInt16(clamping: product)
        return [
            0: String(format: "%04X", UInt16(clamping: vendor)),
            4: String(format: "%02X%02X", UInt8(safeProduct & 0xFF), UInt8(safeProduct >> 8)),
            19: String(format: "%02X%02X", UInt8(clamping: week), UInt8(clamping: year - 1990)),
            30: String(
                format: "%02X%02X",
                UInt8(clamping: horizontalSize / 10),
                UInt8(clamping: verticalSize / 10)
            )
        ]
    }

    private func usesMCDP29XXRoute(entry: io_service_t) -> Bool {
        inheritedStringProperty(entry: entry, key: "EPICProviderClass") == "AppleDCPMCDP29XX"
    }

    private func inheritedStringProperty(entry: io_service_t, key: String) -> String? {
        IORegistryEntrySearchCFProperty(
            entry,
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateParents)
        ) as? String
    }

    private func property(entry: io_registry_entry_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        )?.takeRetainedValue()
    }

    private struct RegistryService {
        var edidUUID = ""
        var productName = ""
        var serialNumber: Int64 = 0
        var ioDisplayLocation = ""
        var service: IOAVService?
        var serviceLocation = 0
        var dcpIndex = -1
        var usesMCDP29XXRoute = false

        var descriptor: DisplayMatchScorer.ServiceDescriptor {
            DisplayMatchScorer.ServiceDescriptor(
                location: ioDisplayLocation,
                productName: productName,
                serialNumber: serialNumber,
                edidUUID: edidUUID
            )
        }
    }

    private struct MatchCandidate {
        let displayID: UInt32
        let service: IOAVService
        let serviceLocation: Int
        let score: Int
        let chipAddress: UInt8
    }
#endif
}
