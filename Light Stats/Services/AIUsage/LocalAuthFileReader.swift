//
//  LocalAuthFileReader.swift
//  Light Stats
//

import Foundation

/// Reads a JSON object from `$HOME/<relativePath>`. Does not request Full Disk Access.
enum LocalAuthFileReader {
    static func readJSON(relativePath: String) -> [String: Any]? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }
}
