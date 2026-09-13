//
//  JSONValueReader.swift
//  Light Stats
//

import Foundation

/// Loose JSON reads for usage endpoints that disagree on types.
///
/// Vendors send the same quantity as a number, a numeric string, a seconds epoch,
/// or a milliseconds epoch, so every read accepts all of them rather than making
/// each provider rediscover the same conversions.
nonisolated enum JSONValueReader {

    /// A JSON amount, whether it arrives as a number or as a numeric string.
    static func double(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let text = value as? String { return Double(text) }
        return nil
    }

    /// An ISO-8601 string, or a Unix epoch in seconds / milliseconds.
    static func date(_ value: Any?) -> Date? {
        if let text = value as? String { return iso8601(text) }
        guard let seconds = double(value), seconds > 1_000_000_000 else { return nil }
        // Millisecond epochs are ~1.7e12 today; a value that large is not seconds.
        return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
    }

    private static func iso8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
