import XCTest
@testable import Light_Stats

final class FinderMenuFileServiceTests: XCTestCase {
    private func sandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testImportedBinarySurvivesOriginalDeletionAndPreservesName() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("合同 '季度'.docx")
        let bytes = Data([0x50, 0x4b, 0, 0xff, 0x80, 0x0a])
        try bytes.write(to: source)
        let service = FinderMenuFileService(libraryURL: root.appendingPathComponent("library"))
        let template = try await service.importTemplate(from: source)
        try FileManager.default.removeItem(at: source)
        let created = try await service.createFile(from: template, in: root)
        XCTAssertEqual(created.lastPathComponent, "合同 '季度'.docx")
        XCTAssertEqual(try Data(contentsOf: created), bytes)
        XCTAssertTrue(template.content.isEmpty)
        let encoded = try JSONEncoder().encode(template)
        let restored = try JSONDecoder().decode(FinderMenuConfig.TemplateEntry.self, from: encoded)
        XCTAssertEqual(restored.storedFileName, source.lastPathComponent)
    }

    func testPackageTemplateCopiesAllContents() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Note.rtfd", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{\\rtf1 test}".utf8).write(to: source.appendingPathComponent("TXT.rtf"))
        let service = FinderMenuFileService(libraryURL: root.appendingPathComponent("library"))
        let template = try await service.importTemplate(from: source)
        let created = try await service.createFile(from: template, in: root)
        XCTAssertEqual(created.lastPathComponent, "Note 2.rtfd")
        XCTAssertEqual(try Data(contentsOf: created.appendingPathComponent("TXT.rtf")), Data("{\\rtf1 test}".utf8))
    }

    func testOfficePresetsCreateRealPackagedFiles() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FinderMenuFileService(libraryURL: root.appendingPathComponent("library"))
        let config = FinderMenuConfig(enabledTemplateIDs: ["docx", "xlsx", "pptx"])
        XCTAssertEqual(config.resolvedTemplates().count, 3)
        for template in config.resolvedTemplates() {
            let created = try await service.createFile(from: template, in: root)
            let data = try Data(contentsOf: created)
            XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4b, 0x03, 0x04], template.id)
            XCTAssertEqual(created.pathExtension, template.id)
        }
    }

    func testLegacyTextTemplateAndNameCollisionsNeverOverwrite() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FinderMenuFileService(libraryURL: root.appendingPathComponent("library"))
        let template = FinderMenuConfig.TemplateEntry(id: "old", title: "Notes", fileExtension: "md", content: "# hello")
        let first = try await service.createFile(from: template, in: root)
        try Data("keep this".utf8).write(to: first)
        let second = try await service.createFile(from: template, in: root)
        XCTAssertEqual(second.lastPathComponent, "notes 2.md")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "keep this")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "# hello")
    }

    func testRemovingTemplateLeavesOriginalUntouched() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Original.txt")
        try Data("original".utf8).write(to: source)
        let library = root.appendingPathComponent("library")
        let service = FinderMenuFileService(libraryURL: library)
        let template = try await service.importTemplate(from: source)
        try await service.removeTemplate(template)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.appendingPathComponent(template.id).path))
    }

    func testTemplateCannotEscapeDestinationOrLibrary() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FinderMenuFileService(libraryURL: root.appendingPathComponent("library"))
        let badName = FinderMenuConfig.TemplateEntry(id: "x", title: "x", fileExtension: "txt", content: "x",
                                                   defaultBaseName: "../escape")
        do {
            _ = try await service.createFile(from: badName, in: root)
            XCTFail("A template name must not escape its destination")
        } catch FinderMenuFileService.FileError.invalidName { }
        let badPath = FinderMenuConfig.TemplateEntry(id: "../outside", title: "x", fileExtension: "txt", content: "",
                                                   storedFileName: "source.txt")
        do {
            try await service.removeTemplate(badPath)
            XCTFail("Only a UUID library directory may be removed")
        } catch FinderMenuFileService.FileError.missingTemplate { }
    }

    func testCopyPreservesSourceAndReportsPartialFailure() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.txt")
        try Data("new".utf8).write(to: source)
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appendingPathComponent("report.txt"))
        let service = FinderMenuFileService(libraryURL: root.appendingPathComponent("library"))
        let result = try await service.transfer(paths: [source.path, root.appendingPathComponent("missing").path],
                                                to: destination, move: false)
        XCTAssertEqual(result.completed, 1)
        XCTAssertEqual(result.failed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("report.txt"), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("report 2.txt"), encoding: .utf8), "new")
    }

    func testMoveIntoSameDirectoryDoesNotRenameAndMoveElsewhereRemovesSource() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.txt")
        try Data("report".utf8).write(to: source)
        let service = FinderMenuFileService(libraryURL: root.appendingPathComponent("library"))
        let same = try await service.transfer(paths: [source.path], to: root, move: true)
        XCTAssertEqual(same.failed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("report 2.txt").path))
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let moved = try await service.transfer(paths: [source.path], to: destination, move: true)
        XCTAssertEqual(moved.completed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("report.txt").path))
    }

    func testCannotTransferFolderInsideItselfIncludingSymlinkDestination() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("project")
        let child = folder.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: child)
        let service = FinderMenuFileService(libraryURL: root.appendingPathComponent("library"))
        let result = try await service.transfer(paths: [folder.path], to: link, move: false)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.completed, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: child.path), [])
    }

    func testFolderNamesContainingDotsKeepTheirNameOnCollision() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("project.v2")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let service = FinderMenuFileService(libraryURL: root.appendingPathComponent("library"))
        let result = try await service.transfer(paths: [source.path], to: root, move: false)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("project.v2 2").path))
    }

    func testDirectoryContextUsesSelectedFolderAndBlankSpaceContainer() throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Selected")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("file.txt")
        try Data().write(to: file)
        let selected = FinderMenuRequest(action: .openTerminalHere, paths: [folder.path], container: root.path)
        XCTAssertEqual(FinderMenuFileService.directory(for: selected)?.path, folder.path)
        let blank = FinderMenuRequest(action: .newFile, paths: [], container: root.path)
        XCTAssertEqual(FinderMenuFileService.directory(for: blank)?.path, root.path)
        let fileContainer = FinderMenuRequest(action: .openTerminalHere, paths: [], container: file.path)
        XCTAssertEqual(FinderMenuFileService.directory(for: fileContainer)?.path, folder.path)
    }

    func testCopyPathForBlankSpaceAndMultipleSelections() {
        let blank = FinderMenuRequest(action: .copyPath, paths: [], container: "/Users/example/My Folder")
        XCTAssertEqual(FinderMenuFileService.pasteboardText(for: blank), "/Users/example/My Folder")
        let items = FinderMenuRequest(action: .copyPath, paths: ["/a/one.txt", "/b/two.txt"], container: "/a")
        XCTAssertEqual(FinderMenuFileService.pasteboardText(for: items), "/a/one.txt\n/b/two.txt")
    }
}
