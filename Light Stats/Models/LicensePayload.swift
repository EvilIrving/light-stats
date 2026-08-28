import Foundation

/// Decoded, signature-verified contents of an activation code.
struct LicensePayload: Sendable, Equatable {
    /// Premium capabilities a code can grant.
    enum Feature: String, Codable, Sendable, CaseIterable {
        case findMouse
    }

    var features: Set<Feature>
    var owner: String
    var issuedAt: Date
}
