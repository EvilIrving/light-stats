import Foundation

/// Serializes template storage and file transfers away from the UI actor.
actor FinderMenuFileService {
    static let shared = FinderMenuFileService()

    struct TransferResult: Sendable {
        let completed: Int
        let failed: Int
    }

    enum FileError: Error {
        case invalidName, invalidDirectory, missingTemplate, recursiveTransfer, unsupportedTemplate
    }

    private let libraryURL: URL
    private let resourceURL: URL?
    private let fileManager = FileManager.default

    init(libraryURL: URL? = nil, resourceURL: URL? = Bundle.main.resourceURL) {
        self.libraryURL = libraryURL ?? URL.applicationSupportDirectory
            .appendingPathComponent("Light Stats/Finder Templates", isDirectory: true)
        self.resourceURL = resourceURL
    }

    func importTemplate(from source: URL) throws -> FinderMenuConfig.TemplateEntry {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true || values.isPackage == true else {
            throw FileError.unsupportedTemplate
        }
        let id = UUID().uuidString
        let folder = libraryURL.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
        return FinderMenuConfig.TemplateEntry(
            id: id, title: source.lastPathComponent, fileExtension: source.pathExtension, content: "",
            defaultBaseName: source.deletingPathExtension().lastPathComponent,
            storedFileName: source.lastPathComponent
        )
    }

    func removeTemplate(_ template: FinderMenuConfig.TemplateEntry) throws {
        guard template.storedFileName != nil else { return }
        let stored = try storedURL(for: template)
        let folder = stored.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: folder.path) else { return }
        try fileManager.removeItem(at: folder)
    }

    func createFile(from template: FinderMenuConfig.TemplateEntry, in directory: URL) throws -> URL {
        try validateDirectory(directory)
        let base = template.defaultBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = base.isEmpty ? FinderMenuPresets.defaultBaseName(forExtension: template.fileExtension) : base
        try validateName(name)
        if !template.fileExtension.isEmpty { try validateName(template.fileExtension) }
        let destination = uniqueURL(in: directory, baseName: name, extension: template.fileExtension)
        if template.storedFileName != nil {
            try fileManager.copyItem(at: storedURL(for: template), to: destination)
        } else if let filename = FinderMenuPresets.bundledFileName(for: template.id) {
            guard let source = resourceURL?.appendingPathComponent(filename), fileManager.fileExists(atPath: source.path) else {
                throw FileError.missingTemplate
            }
            try fileManager.copyItem(at: source, to: destination)
        } else {
            // Exclusive creation must never overwrite a file created after the name check.
            try Data(template.content.utf8).write(to: destination, options: .withoutOverwriting)
        }
        return destination
    }

    func transfer(paths: [String], to directory: URL, move: Bool) throws -> TransferResult {
        try validateDirectory(directory)
        let destination = directory.resolvingSymlinksInPath().standardizedFileURL
        var completed = 0
        var failed = 0
        for path in paths {
            let source = URL(fileURLWithPath: path)
            do {
                try transferItem(source, to: destination, move: move)
                completed += 1
            } catch {
                failed += 1
                DiagnosticLogService.record(
                    level: .error, category: "finderMenu", action: "transferItemFailed",
                    fields: ["operation": move ? "move" : "copy", "reason": String(describing: type(of: error))]
                )
            }
        }
        return TransferResult(completed: completed, failed: failed)
    }

    private func transferItem(_ source: URL, to directory: URL, move: Bool) throws {
        let resolved = source.resolvingSymlinksInPath().standardizedFileURL
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if move && source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == directory { return }
        guard directory != resolved, !directory.path.hasPrefix(resolved.path + "/") else {
            throw FileError.recursiveTransfer
        }
        let isFolder = values.isDirectory == true && values.isPackage != true
        let base = isFolder ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        let ext = isFolder ? "" : source.pathExtension
        let target = uniqueURL(in: directory, baseName: base, extension: ext)
        if move {
            try fileManager.moveItem(at: source, to: target)
        } else {
            try fileManager.copyItem(at: source, to: target)
        }
    }

    private func storedURL(for template: FinderMenuConfig.TemplateEntry) throws -> URL {
        guard UUID(uuidString: template.id) != nil, let name = template.storedFileName else {
            throw FileError.missingTemplate
        }
        try validateName(name)
        return libraryURL.appendingPathComponent(template.id, isDirectory: true).appendingPathComponent(name)
    }

    private func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\0") else { throw FileError.invalidName }
    }

    private func validateDirectory(_ directory: URL) throws {
        guard directory.isFileURL,
              try directory.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw FileError.invalidDirectory
        }
    }

    private func uniqueURL(in directory: URL, baseName: String, extension fileExtension: String) -> URL {
        func candidate(_ index: Int) -> URL {
            let name = index == 1 ? baseName : "\(baseName) \(index)"
            let url = directory.appendingPathComponent(name)
            return fileExtension.isEmpty ? url : url.appendingPathExtension(fileExtension)
        }
        var index = 1
        while fileManager.fileExists(atPath: candidate(index).path) { index += 1 }
        return candidate(index)
    }

    /// Item menus act on the selected folder; blank-space menus carry only a container.
    nonisolated static func directory(for request: FinderMenuRequest) -> URL? {
        guard let path = request.paths.first ?? request.container, !path.isEmpty, path.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return nil }
        return values.isDirectory == true && values.isPackage != true ? url : url.deletingLastPathComponent()
    }

    nonisolated static func pasteboardText(for request: FinderMenuRequest) -> String {
        let paths = request.paths.isEmpty ? [request.container].compactMap { $0 } : request.paths
        if request.action == .copyName {
            return paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n")
        }
        return paths.joined(separator: "\n")
    }
}
