//
//  DiagnosticReportService.swift
//  Light Stats
//
//  User-initiated support report: environment baseline, fresh capability probes,
//  relevant settings, and the bounded local journal in one ZIP archive.
//

import Darwin
import Foundation

actor DiagnosticReportService {
    enum ReportError: LocalizedError {
        case archiveFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .archiveFailed(let status):
                return "Diagnostic archive failed with status \(status)"
            }
        }
    }

    static let shared = DiagnosticReportService()

    private let journalDirectory: URL
    private let collectsFreshProbes: Bool
    private let recordsLifecycleEvents: Bool

    init(
        journalDirectory: URL = DiagnosticLogService.diagnosticsDirectoryURL,
        collectsFreshProbes: Bool = true,
        recordsLifecycleEvents: Bool = true
    ) {
        self.journalDirectory = journalDirectory
        self.collectsFreshProbes = collectsFreshProbes
        self.recordsLifecycleEvents = recordsLifecycleEvents
    }

    nonisolated static func suggestedFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Light-Stats-Diagnostics-\(formatter.string(from: date)).zip"
    }

    nonisolated static func recordEnvironmentBaseline() {
        DiagnosticLogService.recordState(
            category: "environment",
            action: "baseline",
            fields: environmentFields().mapValues(DiagnosticLogService.Field.privateValue)
        )
    }

    func createReport(at destinationURL: URL, settings: [String: String]) async throws -> URL {
        if recordsLifecycleEvents {
            DiagnosticLogService.record(category: "diagnostics", action: "exportRequested")
        }

        let capabilities: [String: Any]
        if collectsFreshProbes {
            let battery = await PowerService().current()
            let cpuTemperature = await SMCInfo.getCPUTemperature()
            let fanSpeed = await SMCInfo.getFanSpeed()
            let gpuUsage = await GPUInfo.getGPUUsage()
            capabilities = capabilityObject(
                battery: battery,
                cpuTemperature: cpuTemperature,
                fanSpeed: fanSpeed,
                gpuUsage: gpuUsage
            )
            await DiagnosticLogService.shared.flush()
        } else {
            capabilities = capabilityObject(
                battery: nil,
                cpuTemperature: nil,
                fanSpeed: nil,
                gpuUsage: nil
            )
        }

        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("Light-Stats-Diagnostics-\(UUID().uuidString)", isDirectory: true)
        let reportDirectory = stagingRoot.appendingPathComponent("Light Stats Diagnostics", isDirectory: true)
        try fileManager.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try writeJSON(
            [
                "reportSchemaVersion": 1,
                "createdAt": ISO8601DateFormatter().string(from: Date()),
                "sessionID": DiagnosticLogService.sessionID,
                "privacy": "No serial numbers, credentials, usernames, or full home paths are included."
            ],
            to: reportDirectory.appendingPathComponent("manifest.json")
        )
        try writeJSON(Self.environmentObject(), to: reportDirectory.appendingPathComponent("environment.json"))
        try writeJSON(settings, to: reportDirectory.appendingPathComponent("settings.json"))
        try writeJSON(capabilities, to: reportDirectory.appendingPathComponent("capabilities.json"))
        try copyJournal(to: reportDirectory.appendingPathComponent("journal", isDirectory: true))

        let archiveURL = stagingRoot.appendingPathComponent("report.zip")
        try await archive(directory: reportDirectory, to: archiveURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: archiveURL, to: destinationURL)

        if recordsLifecycleEvents {
            DiagnosticLogService.record(
                category: "diagnostics",
                action: "exportCompleted"
            )
        }
        return destinationURL
    }

    private static func environmentObject() -> [String: Any] {
        environmentFields().mapValues { fieldValue in
            switch fieldValue {
            case .string(let value): return value
            case .integer(let value): return value
            case .unsignedInteger(let value): return value
            case .double(let value): return value
            case .bool(let value): return value
            case .null: return NSNull()
            case .array, .object: return String(describing: fieldValue)
            }
        }
    }

    private static func environmentFields() -> [String: DiagnosticLogService.Value] {
        let processInfo = ProcessInfo.processInfo
        return [
            "app.version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"),
            "app.build": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"),
            "os.version": .string(processInfo.operatingSystemVersionString),
            "os.build": .string(sysctlString("kern.osversion") ?? "unknown"),
            "hardware.model": .string(sysctlString("hw.model") ?? "unknown"),
            "hardware.machine": .string(sysctlString("hw.machine") ?? "unknown"),
            "hardware.processor": .string(sysctlString("machdep.cpu.brand_string") ?? "unknown"),
            "hardware.memoryBytes": sysctlUInt64("hw.memsize").map(DiagnosticLogService.Value.unsignedInteger) ?? .null,
            "hardware.processorCount": .integer(Int64(processInfo.processorCount)),
            "hardware.activeProcessorCount": .integer(Int64(processInfo.activeProcessorCount)),
            "process.uptimeSeconds": .double(processInfo.systemUptime),
            "process.sandboxed": .bool(processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil),
            "locale.identifier": .string(Locale.current.identifier),
            "timezone.identifier": .string(TimeZone.current.identifier)
        ]
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private func capabilityObject(
        battery: BatteryInfo?,
        cpuTemperature: Double?,
        fanSpeed: Int?,
        gpuUsage: Double?
    ) -> [String: Any] {
        let batteryAvailable = battery.map { $0.state != .noBattery }
        return [
            "probeCollectionEnabled": collectsFreshProbes,
            "battery": [
                "available": jsonValue(batteryAvailable),
                "state": battery.map { String(describing: $0.state) } ?? "notCollected",
                "percent": jsonValue(battery?.percent),
                "cycleCount": jsonValue(battery?.cycleCount),
                "healthPercent": jsonValue(battery?.healthPercent),
                "conditionOK": jsonValue(battery?.conditionOK),
                "powerWatts": jsonValue(battery?.powerWatts),
                "temperatureCelsius": jsonValue(battery?.temperature)
            ],
            "cpuTemperature": [
                "available": cpuTemperature != nil,
                "celsius": jsonValue(cpuTemperature)
            ],
            "fan": [
                "available": fanSpeed != nil,
                "rpm": jsonValue(fanSpeed)
            ],
            "gpu": [
                "available": gpuUsage != nil,
                "utilizationPercent": jsonValue(gpuUsage)
            ]
        ]
    }

    private func jsonValue<T>(_ value: T?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func copyJournal(to destination: URL) throws {
        let fileManager = FileManager.default
        let source = journalDirectory
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: source.path) else { return }

        let files = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for file in files where file.lastPathComponent.hasPrefix("diagnostics-") && file.pathExtension == "jsonl" {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
            let filtered = lines.filter(shouldIncludeJournalLine)
            guard !filtered.isEmpty else { continue }
            let output = filtered.joined(separator: "\n") + "\n"
            try output.write(
                to: destination.appendingPathComponent(file.lastPathComponent),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func shouldIncludeJournalLine(_ line: Substring) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return true
        }
        return object["category"] as? String != "selfMonitoring"
    }

    private func archive(directory: URL, to destination: URL) async throws {
        let status = try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", directory.path, destination.path]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
        guard status == 0 else { throw ReportError.archiveFailed(status) }
    }
}
