//
//  DiagnosticReportService.swift
//  Light Stats
//
//  User-initiated support report: environment baseline, fresh capability probes
//  (each with the reason it has no value), relevant settings, a readable digest of
//  the journal, and the bounded local journal itself, in one ZIP archive.
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

    /// Categories kept in the app-owned journal but never shipped in a support report.
    /// Declared in the manifest so a reader knows the package is not the whole story.
    nonisolated static let journalExcludedCategories: Set<String> = ["selfMonitoring"]

    /// Report layout version. Bumped when files are added or a field changes meaning.
    nonisolated static let reportSchemaVersion = 2

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
            let powerService = PowerService()
            let battery = await powerService.current()
            let batteryReasons = await powerService.probeReasonCodes()
            capabilities = capabilityObject(
                battery: battery,
                batteryReasons: batteryReasons,
                cpuTemperature: SMCInfo.getCPUTemperatureProbe(),
                fan: SMCInfo.getFanProbe(),
                gpu: GPUInfo.getGPUUsageProbe()
            )
            await DiagnosticLogService.shared.flush()
        } else {
            capabilities = capabilityObject(
                battery: nil,
                batteryReasons: [:],
                cpuTemperature: .notCollected,
                fan: .notCollected,
                gpu: .notCollected
            )
        }

        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("Light-Stats-Diagnostics-\(UUID().uuidString)", isDirectory: true)
        let reportDirectory = stagingRoot.appendingPathComponent("Light Stats Diagnostics", isDirectory: true)
        try fileManager.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let journalInputs = try copyJournal(to: reportDirectory.appendingPathComponent("journal", isDirectory: true))
        let digest = DiagnosticJournalSummary.build(files: journalInputs)

        try writeJSON(
            [
                "reportSchemaVersion": Self.reportSchemaVersion,
                "createdAt": ISO8601DateFormatter().string(from: Date()),
                "sessionID": DiagnosticLogService.sessionID,
                "privacy": "No serial numbers, credentials, usernames, or full home paths are included.",
                "contents": [
                    "manifest.json",
                    "environment.json",
                    "settings.json",
                    "capabilities.json",
                    "summary.json",
                    "sessions.json",
                    "journal/"
                ],
                "journalPolicy": DiagnosticLogService.journalPolicyDescription(),
                "journalExcludedCategories": Self.journalExcludedCategories.sorted(),
                "journalFiles": journalInputs.map { input in
                    [
                        "name": input.name,
                        "bytes": input.bytes,
                        "excludedRecords": input.excludedRecords
                    ]
                }
            ],
            to: reportDirectory.appendingPathComponent("manifest.json")
        )
        try writeJSON(Self.environmentObject(), to: reportDirectory.appendingPathComponent("environment.json"))
        try writeJSON(settings, to: reportDirectory.appendingPathComponent("settings.json"))
        try writeJSON(capabilities, to: reportDirectory.appendingPathComponent("capabilities.json"))
        try writeJSON(digest.summary, to: reportDirectory.appendingPathComponent("summary.json"))
        try writeJSON(digest.sessions, to: reportDirectory.appendingPathComponent("sessions.json"))

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
            "os.versionNumber": .string(versionNumber(processInfo.operatingSystemVersion)),
            "os.build": .string(sysctlString("kern.osversion") ?? "unknown"),
            "hardware.model": .string(sysctlString("hw.model") ?? "unknown"),
            "hardware.machine": .string(sysctlString("hw.machine") ?? "unknown"),
            "hardware.processor": .string(sysctlString("machdep.cpu.brand_string") ?? "unknown"),
            "hardware.memoryBytes": sysctlUInt64("hw.memsize").map(DiagnosticLogService.Value.unsignedInteger) ?? .null,
            "hardware.processorCount": .integer(Int64(processInfo.processorCount)),
            "hardware.activeProcessorCount": .integer(Int64(processInfo.activeProcessorCount)),
            // 系统开机时长（不是本进程的）：两次会话里数值变小 = 期间重启过。
            "system.uptimeSeconds": .double(processInfo.systemUptime),
            "process.sandboxed": .bool(processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil),
            "locale.identifier": .string(Locale.current.identifier),
            "timezone.identifier": .string(TimeZone.current.identifier)
        ]
    }

    /// `ProcessInfo.operatingSystemVersionString` is localized; this is the parseable form.
    private static func versionNumber(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
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

    /// 每个能力块除了值，还要带「为什么没有值」——支持报告的第一个文件必须是能自证的。
    private func capabilityObject(
        battery: BatteryInfo?,
        batteryReasons: [String: String],
        cpuTemperature: SMCInfo.TemperatureProbe,
        fan: SMCInfo.FanProbe,
        gpu: GPUInfo.GPUProbe
    ) -> [String: Any] {
        let batteryAvailable = battery.map { $0.state != .noBattery }
        var batteryBlock: [String: Any] = [
            "available": optionalJSONValue(batteryAvailable),
            "state": battery.map { String(describing: $0.state) } ?? "notCollected",
            "percent": optionalJSONValue(battery?.percent),
            "cycleCount": optionalJSONValue(battery?.cycleCount),
            "healthPercent": optionalJSONValue(battery?.healthPercent),
            "systemHealthPercent": optionalJSONValue(battery?.systemHealthPercent),
            "conditionOK": optionalJSONValue(battery?.conditionOK),
            "powerWatts": optionalJSONValue(battery?.powerWatts),
            "temperatureCelsius": optionalJSONValue(battery?.temperature)
        ]
        if !collectsFreshProbes {
            batteryBlock["reasonCodes"] = ["all": "notCollected"]
        } else if battery?.state == .noBattery {
            batteryBlock["reasonCodes"] = ["all": "noBattery"]
        } else {
            batteryBlock["reasonCodes"] = batteryReasons
        }

        return [
            "probeCollectionEnabled": collectsFreshProbes,
            "battery": batteryBlock,
            "cpuTemperature": [
                "available": cpuTemperature.celsius != nil,
                "celsius": optionalJSONValue(cpuTemperature.celsius),
                "reasonCode": cpuTemperature.reasonCode,
                "acceptedKeyCount": cpuTemperature.acceptedKeyCount,
                "usedCachedValue": cpuTemperature.usedCachedValue
            ],
            "fan": [
                "available": fan.rpm != nil,
                "rpm": optionalJSONValue(fan.rpm),
                "reasonCode": fan.reasonCode,
                "fanCount": optionalJSONValue(fan.fanCountFromSMC),
                "attempts": SMCInfo.fanEvidenceValues(fan).map(Self.jsonValue)
            ],
            "gpu": [
                "available": gpu.usage != nil,
                "utilizationPercent": optionalJSONValue(gpu.usage),
                "reasonCode": gpu.reasonCode,
                "selectedKey": optionalJSONValue(gpu.selectedKey)
            ]
        ]
    }

    private func optionalJSONValue<T>(_ value: T?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    /// `DiagnosticLogService.Value` → 能直接交给 JSONSerialization 的对象。
    nonisolated static func jsonValue(_ value: DiagnosticLogService.Value) -> Any {
        switch value {
        case .string(let string): return string
        case .integer(let integer): return integer
        case .unsignedInteger(let unsigned): return unsigned
        case .double(let double): return double
        case .bool(let bool): return bool
        case .null: return NSNull()
        case .array(let values): return values.map { Self.jsonValue($0) }
        case .object(let values): return values.mapValues { Self.jsonValue($0) }
        }
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    /// Writes the report's copy of the journal and reports back what went in, so the
    /// manifest can state the coverage instead of leaving it to be discovered.
    private func copyJournal(to destination: URL) throws -> [DiagnosticJournalSummary.FileInput] {
        let fileManager = FileManager.default
        let source = journalDirectory
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: source.path) else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var inputs: [DiagnosticJournalSummary.FileInput] = []
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
            inputs.append(DiagnosticJournalSummary.FileInput(
                name: file.lastPathComponent,
                bytes: output.utf8.count,
                copiedLines: filtered.map(String.init),
                excludedRecords: lines.count - filtered.count
            ))
        }
        return inputs.sorted { $0.name < $1.name }
    }

    private func shouldIncludeJournalLine(_ line: Substring) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return true
        }
        guard let category = object["category"] as? String else { return true }
        return !Self.journalExcludedCategories.contains(category)
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
