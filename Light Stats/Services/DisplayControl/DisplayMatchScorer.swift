//
//  DisplayMatchScorer.swift
//  Light Stats
//

import Foundation

nonisolated enum DisplayMatchScorer {
    struct DisplayDescriptor: Sendable {
        let location: String
        let productName: String
        let serialNumber: Int64
        let edidFragments: [Int: String]
    }

    struct ServiceDescriptor: Sendable {
        let location: String
        let productName: String
        let serialNumber: Int64
        let edidUUID: String
    }

    static func score(display: DisplayDescriptor, service: ServiceDescriptor) -> Int {
        var score = 0

        if !display.location.isEmpty, display.location == service.location {
            score += 10
        }
        if !display.productName.isEmpty,
           display.productName.caseInsensitiveCompare(service.productName) == .orderedSame {
            score += 2
        }
        if display.serialNumber != 0, display.serialNumber == service.serialNumber {
            score += 3
        }

        for (location, fragment) in display.edidFragments where fragment != "0000" {
            let prefix = service.edidUUID.prefix(location + fragment.count)
            if prefix.suffix(fragment.count).caseInsensitiveCompare(fragment) == .orderedSame {
                score += 1
            }
        }
        return score
    }
}
