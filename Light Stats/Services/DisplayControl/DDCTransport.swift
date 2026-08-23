//
//  DDCTransport.swift
//  Light Stats
//

import Foundation
import IOKit

actor DDCTransport {
    private static let dataAddress: UInt32 = 0x51
    private static let replyLength = 11
    private static let watchdogDuration: Duration = .seconds(2)

    private let logger = AppLogger(category: "DisplayControl")
    private var activeKernelCallID: UUID?

    func read(
        route: DDCServiceRoute,
        code: DDCVCPCode,
        retries: Int = 3
    ) async -> DDCPacketCodec.Reply? {
#if arch(arm64)
        let packet = DDCPacketCodec.readRequest(vcpCode: code.rawValue)
        for _ in 0..<max(1, retries) {
            var wrotePacket = false
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(10))
                if await writePacket(packet, route: route) {
                    wrotePacket = true
                }
            }
            guard wrotePacket else {
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }

            try? await Task.sleep(for: .milliseconds(50))
            guard let bytes = await readReply(route: route),
                  let reply = DDCPacketCodec.parseReply(bytes, expectedVCPCode: code.rawValue)
            else {
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }
            return reply
        }
#else
        _ = route
        _ = code
        _ = retries
#endif
        return nil
    }

    func write(
        route: DDCServiceRoute,
        code: DDCVCPCode,
        value: UInt16,
        retries: Int = 3
    ) async -> Bool {
#if arch(arm64)
        let packet = DDCPacketCodec.writeRequest(vcpCode: code.rawValue, value: value)
        for _ in 0..<max(1, retries) {
            var success = false
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(10))
                if await writePacket(packet, route: route) {
                    success = true
                }
            }
            if success {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
#else
        _ = route
        _ = code
        _ = value
        _ = retries
#endif
        return false
    }

#if arch(arm64)
    private func writePacket(_ source: [UInt8], route: DDCServiceRoute) async -> Bool {
        let result = await runKernelCall { [source, route] in
            var packet = source
            let status = packet.withUnsafeMutableBytes { buffer -> IOReturn in
                guard let address = buffer.baseAddress else { return kIOReturnBadArgument }
                return IOAVServiceWriteI2C(
                    route.service,
                    UInt32(route.chipAddress),
                    Self.dataAddress,
                    address,
                    UInt32(buffer.count)
                )
            }
            return KernelCallResult(status: status, bytes: [])
        }
        return result?.status == KERN_SUCCESS
    }

    private func readReply(route: DDCServiceRoute) async -> [UInt8]? {
        let result = await runKernelCall { [route] in
            var bytes = [UInt8](repeating: 0, count: Self.replyLength)
            let status = bytes.withUnsafeMutableBytes { buffer -> IOReturn in
                guard let address = buffer.baseAddress else { return kIOReturnBadArgument }
                return IOAVServiceReadI2C(
                    route.service,
                    UInt32(route.chipAddress),
                    0,
                    address,
                    UInt32(buffer.count)
                )
            }
            return KernelCallResult(status: status, bytes: bytes)
        }
        guard let result, result.status == KERN_SUCCESS else { return nil }
        return result.bytes
    }

    private func runKernelCall(
        _ operation: @escaping @Sendable () -> KernelCallResult
    ) async -> KernelCallResult? {
        guard activeKernelCallID == nil else {
            logger.error("Skipped DDC I/O while a timed-out kernel call is still active")
            return nil
        }

        let callID = UUID()
        activeKernelCallID = callID
        let result: KernelCallResult? = await withCheckedContinuation { (continuation: CheckedContinuation<KernelCallResult?, Never>) in
            let watchdog = DDCWatchdogBox<KernelCallResult>(continuation: continuation)
            Thread.detachNewThread { [weak self] in
                let result = operation()
                watchdog.resolve(result)
                Task {
                    await self?.kernelCallDidFinish(callID)
                }
            }
            Task.detached {
                try? await Task.sleep(for: Self.watchdogDuration)
                watchdog.resolve(nil)
            }
        }

        if result != nil, activeKernelCallID == callID {
            activeKernelCallID = nil
        } else if result == nil {
            logger.error("DDC kernel call exceeded the 2 second watchdog")
        }
        return result
    }

    private func kernelCallDidFinish(_ callID: UUID) {
        if activeKernelCallID == callID {
            activeKernelCallID = nil
        }
    }

    private struct KernelCallResult: Sendable {
        let status: IOReturn
        let bytes: [UInt8]
    }
#endif
}

#if arch(arm64)
nonisolated private final class DDCWatchdogBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var didResolve = false

    init(continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: Value?) {
        lock.lock()
        guard !didResolve else {
            lock.unlock()
            return
        }
        didResolve = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
#endif
