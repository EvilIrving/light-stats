//
//  DeviceDisplayNameResolver.swift
//  Light Stats
//

import Foundation

nonisolated final class DeviceDisplayNameResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedName: String?

    func deviceDisplayName() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedName {
            return cachedName
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["SPHardwareDataType"] as? [[String: Any]],
              let machineName = entries.first?["machine_name"] as? String,
              !machineName.isEmpty
        else {
            return nil
        }

        cachedName = machineName
        return machineName
    }
}
