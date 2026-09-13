import AppKit

@MainActor
enum FinderMenuTerminalService {
    static func open(id: String, at directory: URL) async -> Bool {
        let preset = FinderMenuPresets.terminalPreset(id: id)
        guard let bundleID = preset.bundleID,
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return false }
        let arguments: [String]
        switch preset.id {
        case "ghostty", "alacritty": arguments = ["--working-directory=\(directory.path)"]
        case "wezterm": arguments = ["start", "--cwd", directory.path]
        case "kitty": arguments = ["--directory", directory.path]
        default: return await openApplication(bundleID: bundleID, urls: [directory])
        }
        return await FinderMenuSystemService.run("/usr/bin/open", arguments: ["-n", "-b", bundleID, "--args"] + arguments) == 0
    }

    static func openApplication(bundleID: String, urls: [URL]) async -> Bool {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: configuration)
            return true
        } catch {
            return false
        }
    }
}
