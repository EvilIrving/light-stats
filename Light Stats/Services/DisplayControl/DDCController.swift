//
//  DDCController.swift
//  Light Stats
//

import CoreGraphics
import Foundation

actor DDCController {
    struct ProbeResult: Sendable {
        let capability: DisplayControlCapability
        let brightness: Double?
    }

    private let matcher: DisplayServiceMatcher
    private let transport: DDCTransport
    private let capabilityCache: DDCCapabilityCache
    private let gate: DDCEnvironmentGate
    private var routes: [UInt32: DDCServiceRoute] = [:]

    init(
        matcher: DisplayServiceMatcher = DisplayServiceMatcher(),
        transport: DDCTransport = DDCTransport(),
        capabilityCache: DDCCapabilityCache = DDCCapabilityCache(),
        gate: DDCEnvironmentGate
    ) {
        self.matcher = matcher
        self.transport = transport
        self.capabilityCache = capabilityCache
        self.gate = gate
    }

    func refreshRoutes(displayIDs: [CGDirectDisplayID]) {
        routes = matcher.matchedServices(displayIDs: displayIDs)
        capabilityCache.retain(displayIDs: Set(displayIDs))
    }

    func resetHungBus() async {
        await transport.resetHungState()
    }

    func isBusHung() async -> Bool {
        await transport.isHung
    }

    func probeBrightness(displayID: UInt32) async -> ProbeResult {
        guard let route = routes[displayID] else {
            return ProbeResult(capability: .unsupported, brightness: nil)
        }
        guard !gate.isSuppressed else {
            return ProbeResult(
                capability: capabilityCache.entry(for: displayID).capability,
                brightness: nil
            )
        }

        for code in orderedCandidates(displayID: displayID) {
            guard let reply = await transport.read(route: route, code: code) else { continue }
            guard reply.resultCode == 0, reply.maximum > 0 else { continue }

            let maximum = DDCRawConversion.sanitizedMaximum(reply.maximum)
            capabilityCache.setSupported(displayID: displayID, code: code, maximum: maximum)
            return ProbeResult(
                capability: .supported,
                brightness: DDCRawConversion.percent(rawValue: reply.current, maximum: maximum)
            )
        }

        capabilityCache.setUnsupported(displayID: displayID)
        return ProbeResult(capability: .unsupported, brightness: nil)
    }

    func readBrightness(displayID: UInt32) async -> Double? {
        guard !gate.isSuppressed,
              let route = routes[displayID]
        else {
            return nil
        }

        let entry = capabilityCache.entry(for: displayID)
        guard entry.capability != .unsupported else { return nil }
        let code = entry.code ?? .luminance
        guard let reply = await transport.read(route: route, code: code),
              reply.resultCode == 0,
              reply.maximum > 0
        else {
            if await transport.isHung {
                capabilityCache.setUnsupported(displayID: displayID)
            }
            return nil
        }

        let maximum = DDCRawConversion.sanitizedMaximum(reply.maximum)
        capabilityCache.setSupported(displayID: displayID, code: code, maximum: maximum)
        return DDCRawConversion.percent(rawValue: reply.current, maximum: maximum)
    }

    func writeBrightness(_ percent: Double, displayID: UInt32) async -> Bool {
        guard !gate.isSuppressed,
              let route = routes[displayID]
        else {
            return false
        }

        let entry = capabilityCache.entry(for: displayID)
        guard entry.capability != .unsupported else { return false }
        let maximum = entry.maximum ?? 100
        let rawValue = DDCRawConversion.rawValue(percent: percent, maximum: maximum)

        for code in orderedCandidates(displayID: displayID) {
            guard await transport.write(route: route, code: code, value: rawValue) else { continue }
            capabilityCache.setPreferredCode(displayID: displayID, code: code, maximum: maximum)
            return true
        }
        if await transport.isHung {
            capabilityCache.setUnsupported(displayID: displayID)
        }
        return false
    }

    func stop() async {
        routes.removeAll()
        capabilityCache.retain(displayIDs: [])
        await transport.resetHungState()
    }

    private func orderedCandidates(displayID: UInt32) -> [DDCVCPCode] {
        let candidates = DDCVCPCode.brightnessCandidates
        guard let preferred = capabilityCache.entry(for: displayID).code else {
            return candidates
        }
        return [preferred] + candidates.filter { $0 != preferred }
    }
}
