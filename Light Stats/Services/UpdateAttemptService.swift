import Foundation
import Darwin

/// Bridges failures across app termination without enabling background network activity.
actor UpdateAttemptService {
    private let directory: URL
    private var ownership: FileHandle?

    enum AttemptError: LocalizedError {
        case busy
        case pending

        var errorDescription: String? { "update.error.busy".localized }
    }

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? base.appendingPathComponent("Light Stats/Updates", isDirectory: true)
    }

    private var attemptURL: URL { directory.appendingPathComponent("attempt.json") }
    var resultURL: URL { directory.appendingPathComponent("result.txt") }
    private var backupRecordURL: URL { directory.appendingPathComponent("result.txt.backup") }

    func begin(sourceVersion: String, release: ReleaseInfo, destination: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try acquireOwnership()
        guard !FileManager.default.fileExists(atPath: attemptURL.path) else { throw AttemptError.pending }
        // A previous result must never be mistaken for this attempt's outcome.
        for url in [resultURL, backupRecordURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try save(UpdateAttempt(
            sourceVersion: sourceVersion,
            targetVersion: release.tagName,
            bundlePath: destination.resolvingSymlinksInPath().path,
            downloadPage: release.htmlURL,
            stage: "downloading"
        ))
    }

    func advance(to stage: String) throws {
        guard var attempt = try load() else { return }
        attempt.stage = stage
        try save(attempt)
    }

    func staged(_ app: URL) throws {
        guard var attempt = try load() else { return }
        attempt.stage = "replacing"
        attempt.stagedAppPath = app.path
        try save(attempt)
    }

    /// Leave the receipt until the feedback has been displayed and journaled.
    func pending(for bundle: URL) throws -> UpdateAttempt? {
        guard FileManager.default.fileExists(atPath: attemptURL.path) else { return nil }
        try acquireOwnership()
        guard let attempt = try load() else { releaseOwnership(); return nil }
        let current = bundle.resolvingSymlinksInPath().path
        let backupPath = try backup(for: attempt)?.resolvingSymlinksInPath().path
        guard current == attempt.bundlePath || current == backupPath else { releaseOwnership(); return nil }
        return attempt
    }

    func result() throws -> String? {
        guard FileManager.default.fileExists(atPath: resultURL.path) else { return nil }
        return try String(contentsOf: resultURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clear(removeBackup: Bool = false) throws {
        try acquireOwnership()
        defer { releaseOwnership() }
        if let attempt = try load() {
            if removeBackup, let backup = try backup(for: attempt), FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            if let path = attempt.stagedAppPath {
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath()
                let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                if parent.deletingLastPathComponent() == temporary,
                   parent.lastPathComponent.hasPrefix("LightStatsStage-"),
                   FileManager.default.fileExists(atPath: parent.path) {
                    try FileManager.default.removeItem(at: parent)
                }
            }
        }
        for url in [attemptURL, resultURL, backupRecordURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// The child inherits this open file description as stdin. Closing our copy after
    /// launch transfers ownership; explicitly unlocking would also unlock the child.
    func installerOwnership() throws -> FileHandle {
        guard let ownership else { throw AttemptError.busy }
        return ownership
    }

    func releaseOwnership() {
        try? ownership?.close()
        ownership = nil
    }

    private func acquireOwnership() throws {
        guard ownership == nil else { return }
        let path = directory.appendingPathComponent("install.lock").path
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw AttemptError.busy
        }
        ownership = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func backup(for attempt: UpdateAttempt) throws -> URL? {
        guard FileManager.default.fileExists(atPath: backupRecordURL.path) else { return nil }
        let path = try String(contentsOf: backupRecordURL, encoding: .utf8).trimmingCharacters(in: .newlines)
        let backup = URL(fileURLWithPath: path).standardizedFileURL
        let destination = URL(fileURLWithPath: attempt.bundlePath)
        guard backup.deletingLastPathComponent().resolvingSymlinksInPath() == destination.deletingLastPathComponent(),
              backup.lastPathComponent.hasPrefix(".LightStatsUpdate."),
              backup.lastPathComponent.hasSuffix(".backup.app") else { return nil }
        return backup
    }

    /// A successful shell exit alone does not prove that the intended version launched.
    nonisolated static func succeeded(attempt: UpdateAttempt, currentVersion: String, result: String?) -> Bool {
        guard result == "installed",
              let current = SemanticVersion(currentVersion),
              let target = SemanticVersion(attempt.targetVersion) else { return false }
        return current == target
    }

    private func load() throws -> UpdateAttempt? {
        guard FileManager.default.fileExists(atPath: attemptURL.path) else { return nil }
        return try JSONDecoder().decode(UpdateAttempt.self, from: Data(contentsOf: attemptURL))
    }

    private func save(_ attempt: UpdateAttempt) throws {
        try JSONEncoder().encode(attempt).write(to: attemptURL, options: .atomic)
    }
}
