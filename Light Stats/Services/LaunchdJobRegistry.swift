//
//  LaunchdJobRegistry.swift
//  Light Stats
//
//  Reads the launchd jobs installed on this Mac: program path -> job label.
//

import Foundation

/// The installed launchd jobs, as `program path -> label`.
///
/// A privileged helper keeps its executable outside every application bundle, so nothing about the
/// process itself names its product; the job label does. The label cannot be read from a running
/// root process, so the table is built by scanning the three install directories.
///
/// Most jobs name their program in `ProgramArguments[0]`, which makes a shared interpreter the
/// first argument of several unrelated jobs — `/bin/bash` belongs to one job, and every shell on
/// the machine would otherwise be labelled with it. Those paths are not indexed.
///
/// A job installed by an application through `SMAppService` puts its plist inside that application
/// instead, where this scan cannot reach it. That is the case the process's own bundle identifier
/// already covers, because such a job's program is the application's own bundled binary.
///
/// The scan is gated on the directories' modification dates: it runs once, then only after
/// something installs or removes a job.
nonisolated final class LaunchdJobRegistry: @unchecked Sendable {

    static let shared = LaunchdJobRegistry()

    private static let defaultDirectories = [
        "/Library/LaunchDaemons",
        "/Library/LaunchAgents",
        NSHomeDirectory() + "/Library/LaunchAgents"
    ]

    /// Directories whose binaries many unrelated jobs can share.
    private static let sharedBinaryDirectories = [
        "/bin/", "/sbin/", "/usr/bin/", "/usr/sbin/", "/usr/local/bin/", "/opt/homebrew/bin/"
    ]

    private let directories: [String]
    private let lock = NSLock()
    private var labelsByProgramPath: [String: String] = [:]
    private var scannedStamps: [String: Date] = [:]

    init(directories: [String] = LaunchdJobRegistry.defaultDirectories) {
        self.directories = directories
    }

    /// The job label whose program is `path`, or `nil` when no installed job starts that program.
    func label(forProgramPath path: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if needsScan() {
            labelsByProgramPath = Self.labelTable(in: directories)
            scannedStamps = currentStamps()
        }
        return labelsByProgramPath[path]
    }

    private func needsScan() -> Bool {
        guard !scannedStamps.isEmpty else { return true }
        return currentStamps() != scannedStamps
    }

    private func currentStamps() -> [String: Date] {
        var stamps: [String: Date] = [:]
        for directory in directories {
            let attributes = try? FileManager.default.attributesOfItem(atPath: directory)
            if let modified = attributes?[.modificationDate] as? Date {
                stamps[directory] = modified
            }
        }
        return stamps
    }

    /// Reads every job plist in `directories`.
    static func labelTable(in directories: [String]) -> [String: String] {
        var table: [String: String] = [:]
        for directory in directories {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".plist") {
                let path = directory + "/" + entry
                guard let data = FileManager.default.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(
                          from: data,
                          format: nil
                      ) as? [String: Any],
                      let label = plist["Label"] as? String,
                      let program = programPath(in: plist),
                      !isSharedBinary(program)
                else { continue }
                table[program] = label
            }
        }
        return table
    }

    private static func isSharedBinary(_ path: String) -> Bool {
        sharedBinaryDirectories.contains { path.hasPrefix($0) }
    }

    private static func programPath(in plist: [String: Any]) -> String? {
        if let program = plist["Program"] as? String, !program.isEmpty {
            return program
        }
        guard let arguments = plist["ProgramArguments"] as? [String] else { return nil }
        return arguments.first
    }
}
