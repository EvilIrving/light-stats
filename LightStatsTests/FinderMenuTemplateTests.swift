//
//  FinderMenuTemplateTests.swift
//  LightStatsTests
//
//  Created on 2026/06/28.
//
//  Covers the New-File template visibility model: nil = default subset,
//  explicit list (incl. empty) = exactly the user's choice, custom templates
//  always appended, and backward-compatible decoding of old JSON.
//

import XCTest
@testable import Light_Stats

final class FinderMenuTemplateTests: XCTestCase {

    func testNilEnabledUsesDefaultSubset() {
        let config = FinderMenuConfig()   // enabledTemplateIDs == nil
        let ids = config.resolvedTemplates().map(\.id)
        XCTAssertEqual(ids, FinderMenuPresets.defaultEnabledTemplateIDs)
    }

    func testExplicitEmptyShowsNoPresets() {
        let config = FinderMenuConfig(enabledTemplateIDs: [])
        XCTAssertTrue(config.resolvedTemplates().isEmpty)
    }

    func testEnabledPresetsFollowPresetOrderNotSelectionOrder() {
        // Selected out of order → resolved follows the canonical preset order.
        let config = FinderMenuConfig(enabledTemplateIDs: ["html", "txt", "json"])
        let order = FinderMenuPresets.fileTemplates.map(\.id)
        let resolved = config.resolvedTemplates().map(\.id)
        XCTAssertEqual(resolved, order.filter { ["html", "txt", "json"].contains($0) })
        XCTAssertEqual(resolved.first, "txt")   // txt precedes html/json in presets
    }

    func testUnknownEnabledIDsAreIgnored() {
        let config = FinderMenuConfig(enabledTemplateIDs: ["txt", "does-not-exist"])
        XCTAssertEqual(config.resolvedTemplates().map(\.id), ["txt"])
    }

    func testCustomTemplatesAppendedAfterPresets() {
        let custom = FinderMenuConfig.TemplateEntry(id: "custom-1", title: "My (.x)", fileExtension: "x", content: "hi")
        let config = FinderMenuConfig(templates: [custom], enabledTemplateIDs: ["md"])
        let ids = config.resolvedTemplates().map(\.id)
        XCTAssertEqual(ids, ["md", "custom-1"])
    }

    func testDecodingOldJSONWithoutEnabledFieldFallsBackToDefault() throws {
        // Old persisted config had no enabledTemplateIDs key.
        let json = Data(#"{"favoriteDirectories":[],"openWithApps":[],"templates":[]}"#.utf8)
        let config = try JSONDecoder().decode(FinderMenuConfig.self, from: json)
        XCTAssertNil(config.enabledTemplateIDs)
        XCTAssertEqual(config.resolvedTemplates().map(\.id), FinderMenuPresets.defaultEnabledTemplateIDs)
    }

    func testEnabledTemplateIDsSurvivesRoundTrip() throws {
        let original = FinderMenuConfig(enabledTemplateIDs: ["md", "html"])
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(FinderMenuConfig.self, from: data)
        XCTAssertEqual(restored.enabledTemplateIDs, ["md", "html"])
    }

    func testPresetDefaultBaseNamesAreTypeSpecific() {
        let byID = Dictionary(uniqueKeysWithValues: FinderMenuPresets.fileTemplates.map { ($0.id, $0.defaultBaseName) })
        XCTAssertEqual(byID["html"], "index")
        XCTAssertEqual(byID["py"], "main")
        XCTAssertEqual(byID["ts"], "index")
        XCTAssertEqual(byID["txt"], "Document")
        XCTAssertEqual(byID["md"], "notes")
        XCTAssertEqual(byID["css"], "styles")
        XCTAssertEqual(byID["json"], "data")
        // Never the old catch-all.
        for template in FinderMenuPresets.fileTemplates {
            XCTAssertNotEqual(template.defaultBaseName, "Untitled", template.id)
            XCTAssertFalse(template.defaultBaseName.isEmpty, template.id)
        }
    }

    func testResolvedTemplatesCarryDefaultBaseNames() {
        let config = FinderMenuConfig(enabledTemplateIDs: ["html", "py", "txt"])
        let names = Dictionary(uniqueKeysWithValues: config.resolvedTemplates().map { ($0.id, $0.defaultBaseName) })
        XCTAssertEqual(names["html"], "index")
        XCTAssertEqual(names["py"], "main")
        XCTAssertEqual(names["txt"], "Document")
    }

    func testCustomTemplateInfersBaseNameFromExtension() {
        let custom = FinderMenuConfig.TemplateEntry(
            id: "c1", title: "My", fileExtension: "py", content: ""
        )
        XCTAssertEqual(custom.defaultBaseName, "main")
    }

    func testDecodingOldTemplateJSONWithoutBaseNameInfersFromExtension() throws {
        let json = Data(#"""
        {"favoriteDirectories":[],"openWithApps":[],"templates":[
          {"id":"c1","title":"x","fileExtension":"html","content":""}
        ],"enabledTemplateIDs":[]}
        """#.utf8)
        let config = try JSONDecoder().decode(FinderMenuConfig.self, from: json)
        XCTAssertEqual(config.templates.first?.defaultBaseName, "index")
    }
}
