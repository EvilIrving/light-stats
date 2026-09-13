//
//  CredentialSource.swift
//  Light Stats
//

import Foundation

/// How a provider obtains credentials. No I/O.
enum CredentialSource: Equatable, Sendable {
    case localDiscovered
    case apiToken
    case ideDatabase
}
