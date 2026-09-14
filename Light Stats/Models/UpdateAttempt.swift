import Foundation

/// Durable state for one user-requested update. Paths stay local and are never exported.
nonisolated struct UpdateAttempt: Codable, Sendable {
    let sourceVersion: String
    let targetVersion: String
    let bundlePath: String
    let downloadPage: URL
    var stage: String
    var stagedAppPath: String?
}
