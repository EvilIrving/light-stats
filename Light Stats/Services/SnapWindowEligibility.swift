//
//  SnapWindowEligibility.swift
//  Light Stats
//

import Foundation

/// Whether a window may be snapped at all.
///
/// The filter runs in three layers — an Accessibility subrole whitelist, a built-in app blacklist, and
/// geometry/title heuristics — because each layer catches a different failure. Without them a drag
/// that starts on a Chrome toolbar flyout or an Electron modal widget gets tiled, which is the
/// single most common way a window manager feels broken.
nonisolated enum SnapWindowEligibility {

    /// Only these subroles are real, user-movable windows. Everything else — panels, sheets,
    /// popovers, toolbars — is the app's own furniture.
    static let allowedSubroles: Set<String> = [
        "AXStandardWindow",
        "AXDocumentWindow",
        "AXFloatingWindow"
    ]

    /// Apps that break when a third party moves their windows. Kept deliberately short, because
    /// every entry is a window the user cannot snap.
    ///
    /// Browsers, Finder, Preview, Keynote, and every Electron chat client are just as unsnappable in
    /// practice, but they are windows users snap all day long, so they are offered as an opt-in
    /// *recommended* list (`recommendedExclusions`) rather than being forced on.
    static let restrictedBundleIdentifiers: Set<String> = [
        "org.videolan.vlc",          // interrupts playback
        "com.colliderli.iina",
        "com.image-line.flstudio",
        "com.valvesoftware.steam",   // anti-cheat
        "net.battle.bootstrapper",
        "com.blizzard.worldofwarcraft",
        "com.youqu.todesk.mac",      // remote desktop
        "com.microsoft.rdc.macos"
    ]

    /// Wine applications expose no usable window tree and hang on AX writes.
    static let restrictedExecutableNames: Set<String> = ["wine64-preloader"]

    /// Subroles whose windows are worth keeping even when they have no title yet.
    ///
    /// A brand-new document window legitimately has no title for a moment. A floating utility
    /// window with no title is a flyout, and tiling it is the classic "why did my app do that".
    static let untitledTolerantSubroles: Set<String> = [
        "AXStandardWindow",
        "AXDocumentWindow"
    ]

    /// The full recommended set, offered in Settings as a one-click opt-in.
    static let recommendedExclusions: [String] = [
        "com.bilibili.bilibiliPC",
        "com.openai.codex",
        "com.youqu.todesk.mac",
        "com.IdeaPunch.ColorSlurp",
        "com.valvesoftware.steam",
        "com.autodesk.AutoCAD",
        "com.ssworks.drbetotte",
        "com.goland.dvdfab.macos",
        "org.videolan.vlc",
        "org.mozilla.firefox",
        "net.battle.bootstrapper",
        "com.blizzard.worldofwarcraft",
        "com.adobe.AfterEffects",
        "com.adobe.Audition",
        "org.oe-f.OpenBoard",
        "com.apple.dt.Xcode",
        "com.image-line.flstudio",
        "com.colliderli.iina",
        "com.apple.Preview",
        "com.apple.iWork.Keynote",
        "com.apple.iBooksX",
        "com.apple.finder",
        "com.electron.lark",
        "com.alibaba.DingTalkMac",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.apple.MobileSMS",
        "com.apple.FaceTime",
        "ru.keepcoder.Telegram",
        "com.hammerandchisel.discord",
        "com.tencent.WeWorkMac",
        "io.github.clash-verge-rev.clash-verge-rev",
        "com.west2online.ClashX",
        "com.google.Chrome",
        "com.google.android.studio"
    ]

    /// Bundle-identifier prefixes for the whole JetBrains family. A prefix check is exactly
    /// as precise here and cannot be derailed by a malformed pattern.
    static let restrictedBundlePrefixes: [String] = [
        "com.jetbrains.",
        "com.google.android.studio"
    ]

    static func isPreviewable(_ candidate: SnapWindowCandidate, userExclusions: Set<String>) -> Bool {
        var visibleCandidate = candidate
        visibleCandidate.isMinimized = false
        visibleCandidate.isFullScreen = false
        return rejection(for: visibleCandidate, userExclusions: userExclusions, honorsRestrictedList: false) == nil
    }

    /// Why this window may not be snapped, or `nil` when it may.
    ///
    /// The reason strings are stable codes, not prose: they end up in the diagnostic journal and
    /// are what makes a "why did nothing happen" report answerable.
    static func rejection(
        for candidate: SnapWindowCandidate,
        userExclusions: Set<String>,
        honorsRestrictedList: Bool
    ) -> String? {
        if candidate.isMinimized { return "minimized" }
        if candidate.isFullScreen { return "fullScreen" }
        if let roleRejection = roleRejection(for: candidate) { return roleRejection }
        if let appRejection = appRejection(
            for: candidate,
            userExclusions: userExclusions,
            honorsRestrictedList: honorsRestrictedList
        ) {
            return appRejection
        }
        return shapeRejection(for: candidate)
    }

    /// Layer 1 — is this a window at all? Panels, sheets, popovers, and dialogs are the app's own
    /// furniture, not something a person drags around.
    private static func roleRejection(for candidate: SnapWindowCandidate) -> String? {
        if let subrole = candidate.subrole, !subrole.isEmpty {
            if !allowedSubroles.contains(subrole) { return "subrole-\(subrole)" }
        } else if let role = candidate.role, role != "AXWindow" {
            return "role-\(role)"
        }
        if candidate.role == "AXDialog" || candidate.subrole == "AXDialog" {
            return "dialog"
        }
        return nil
    }

    /// Layer 2 — is this an app whose windows must be left alone?
    private static func appRejection(
        for candidate: SnapWindowCandidate,
        userExclusions: Set<String>,
        honorsRestrictedList: Bool
    ) -> String? {
        if let bundleIdentifier = candidate.bundleIdentifier {
            if honorsRestrictedList, isRestricted(bundleIdentifier) { return "restricted-app" }
            if userExclusions.contains(bundleIdentifier) { return "excluded-app" }
        }
        if let executableName = candidate.executableName,
           restrictedExecutableNames.contains(executableName) {
            return "restricted-process"
        }
        return nil
    }

    private static func isRestricted(_ bundleIdentifier: String) -> Bool {
        restrictedBundleIdentifiers.contains(bundleIdentifier)
            || restrictedBundlePrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }

    /// Layer 3 — geometry and title heuristics, for the windows that pass the first two layers and
    /// are still not something a person would call a window.
    private static func shapeRejection(for candidate: SnapWindowCandidate) -> String? {
        guard let frame = candidate.frame else { return "noFrame" }

        let title = (candidate.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            let tolerated = candidate.subrole.map { untitledTolerantSubroles.contains($0) } ?? false
            if !tolerated { return "untitled-non-standard" }
        }
        if title.lowercased().contains("modalwebviewwidget") { return "electron-modal-widget" }
        if frame.width < 40 || frame.height < 40 { return "tooSmall" }
        return nil
    }

    static func isEligible(
        _ candidate: SnapWindowCandidate,
        userExclusions: Set<String> = [],
        honorsRestrictedList: Bool = true
    ) -> Bool {
        rejection(for: candidate, userExclusions: userExclusions, honorsRestrictedList: honorsRestrictedList) == nil
    }

    /// The recommended list plus the hardwired set, for the Settings button.
    static var recommendedExclusionSet: Set<String> {
        Set(recommendedExclusions).union(restrictedBundleIdentifiers)
    }
}
