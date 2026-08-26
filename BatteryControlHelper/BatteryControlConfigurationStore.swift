import Foundation

struct StoredBatteryControlConfiguration: Codable {
    var enabled: Bool
    var upperLimit: Int
    var lowerLimit: Int

    static let disabled = StoredBatteryControlConfiguration(
        enabled: false,
        upperLimit: BatteryControlLimits.defaultUpper,
        lowerLimit: BatteryControlLimits.defaultLower
    )
}

final class BatteryControlConfigurationStore {
    private let fileManager = FileManager.default
    private let directoryURL = URL(fileURLWithPath: "/Library/Application Support/Light Stats")
    private let fileURL = URL(
        fileURLWithPath: "/Library/Application Support/Light Stats/BatteryControl.plist"
    )

    func load() -> StoredBatteryControlConfiguration {
        guard let data = try? Data(contentsOf: fileURL),
              let configuration = try? PropertyListDecoder().decode(
                StoredBatteryControlConfiguration.self,
                from: data
              ) else {
            return .disabled
        }
        return sanitized(configuration)
    }

    func save(_ configuration: StoredBatteryControlConfiguration) throws {
        let configuration = sanitized(configuration)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let data = try PropertyListEncoder().encode(configuration)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
    }

    func clear() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    private func sanitized(
        _ configuration: StoredBatteryControlConfiguration
    ) -> StoredBatteryControlConfiguration {
        let clamped = BatteryControlLimits.clamp(
            upper: configuration.upperLimit,
            lower: configuration.lowerLimit
        )
        return StoredBatteryControlConfiguration(
            enabled: configuration.enabled,
            upperLimit: clamped.upper,
            lowerLimit: clamped.lower
        )
    }
}
