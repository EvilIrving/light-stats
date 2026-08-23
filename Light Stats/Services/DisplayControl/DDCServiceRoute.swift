//
//  DDCServiceRoute.swift
//  Light Stats
//

import Foundation

nonisolated final class DDCServiceRoute: @unchecked Sendable {
    let displayID: UInt32
    let service: IOAVService
    let location: Int
    let matchScore: Int
    let chipAddress: UInt8

    init(
        displayID: UInt32,
        service: IOAVService,
        location: Int,
        matchScore: Int,
        chipAddress: UInt8
    ) {
        self.displayID = displayID
        self.service = service
        self.location = location
        self.matchScore = matchScore
        self.chipAddress = chipAddress
    }
}
