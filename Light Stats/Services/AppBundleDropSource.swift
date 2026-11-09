//
//  AppBundleDropSource.swift
//  Light Stats
//

import Foundation

/// Which bundle a drag into a Privacy list may hand over.
///
/// Both failure modes are invisible at the drop: the list accepts the item, shows a row, and the
/// permission still does not reach the running app. Pure and file-manager-injectable so both rules
/// can be pinned without a window, a pasteboard, or a live Finder.
nonisolated enum AppBundleDropSource {

    /// A quarantined app launched from a DMG or a mounted image runs from
    /// `/private/var/folders/…/AppTranslocation/<UUID>/d/Light Stats.app`. Dragging that registers a
    /// path that stops existing when the process quits, so the row refers to nothing afterwards.
    static let translocationMarker = "/AppTranslocation/"

    /// The bundle to put on the pasteboard, or `nil` when there is nothing honest to drag.
    ///
    /// Symlinks are resolved **before** the translocation test: `/var/folders/…` is itself a symlink
    /// to `/private/var/folders/…`, and the marker is only in the resolved path.
    static func resolvedBundleURL(from url: URL, fileManager: FileManager = .default) -> URL? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.pathExtension == "app" else { return nil }
        guard !isTranslocated(resolved) else { return nil }
        guard fileManager.fileExists(atPath: resolved.path) else { return nil }
        return resolved
    }

    static func isTranslocated(_ url: URL) -> Bool {
        url.path.contains(translocationMarker)
    }

    /// This app's own bundle, through the rules above.
    static var hostBundleURL: URL? {
        resolvedBundleURL(from: Bundle.main.bundleURL)
    }
}
