import AppKit
import Foundation

nonisolated enum FinderMenuSystemService {
    static var showsHiddenFiles: Bool {
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let value = CFPreferencesCopyAppValue("AppleShowAllFiles" as CFString, "com.apple.finder" as CFString)
        if let number = value as? NSNumber { return number.boolValue }
        return ["true", "yes", "1"].contains((value as? String)?.lowercased() ?? "")
    }

    static func setShowsHiddenFiles(_ show: Bool) -> Bool {
        CFPreferencesSetAppValue("AppleShowAllFiles" as CFString, show as CFBoolean, "com.apple.finder" as CFString)
        let saved = CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        FinderMenuShared.setShowsHiddenFiles(showsHiddenFiles)
        return saved && showsHiddenFiles == show
    }

    static func restartFinder() async -> Bool {
        await run("/usr/bin/killall", arguments: ["Finder"]) == 0
    }

    static func run(_ executable: String, arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}
