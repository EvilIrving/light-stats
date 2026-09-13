//
//  AIUsageError.swift
//  Light Stats
//

import Foundation

enum AIUsageError: Error, Equatable {
    case credentialsMissing
    case tokenExpired
    case network
    case decoding
    /// OAuth usage endpoint returned 404 — endpoint may have moved or been disabled.
    case endpointNotFound
}
