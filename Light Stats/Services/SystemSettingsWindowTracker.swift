//
//  SystemSettingsWindowTracker.swift
//  Light Stats
//

import AppKit
import CoreGraphics

/// Finds the System Settings window and follows it while the guide is on screen.
///
/// Everything here reads `CGWindowListCopyWindowInfo`. Owner, bounds and layer need no permission
/// at all — Accessibility would buy a lower-latency frame, but it would also put a new consumer on
/// `AXCommandQueue`, and 120 ms is already faster than a person moves a window.
///
/// The snapshot is a synchronous cross-process call, so every scan goes through `scanFrame` /
/// `scanWindowCount` and runs off the main actor: the card animates at 60 Hz on the main thread
/// while this polls at 8 Hz, and two window-list snapshots per poll in front of that animation is
/// exactly the arrangement the Services contract keeps off Main.
///
/// Two separate jobs, because they have different failure rules:
///
/// - `waitForFrame` waits for the window to *appear and stop moving*. Settings opens on a default
///   size and then resizes itself as the pane loads, so the first frame seen is not where the card
///   should dock.
/// - `startReporting` keeps sending frame updates until the window is gone, so the card stays beside
///   the window the user is dragging around.
@MainActor
final class SystemSettingsWindowTracker {

    /// One poll of the window list, reduced to the facts the picker needs. Accessibility space —
    /// `kCGWindowBounds` is top-left origin, `y` down.
    nonisolated struct Candidate: Equatable, Sendable {
        var ownerName: String
        var ownerPID: pid_t
        var layer: Int
        var bounds: CGRect
    }

    nonisolated static let pollInterval: TimeInterval = 0.12
    /// Nothing at all appeared. The guide cannot dock to a window that does not exist.
    nonisolated static let appearanceTimeout: TimeInterval = 6
    /// Seen, but still moving. Accept the latest frame rather than keeping the user waiting.
    nonisolated static let stabilisationBudget: TimeInterval = 1.2
    nonisolated static let minimumSize = CGSize(width: 300, height: 200)
    /// Consecutive polls without the window before it counts as closed (~400 ms), so a desktop
    /// switch or a momentarily hidden window does not tear the card down.
    nonisolated static let disappearanceMisses = 12

    private let logger = AppLogger(category: "PermissionGuide")
    private var reportingTask: Task<Void, Never>?

    var onFrameChange: ((CGRect) -> Void)?
    var onDisappear: (() -> Void)?

    // MARK: - Appearing

    /// The window's frame in Cocoa screen points, or `nil` if it never appeared.
    ///
    /// Ends at the first frame that matches the previous sample to the pixel. Past the stabilisation
    /// budget the latest sample is returned instead: a window that keeps animating is still a better
    /// dock target than no card, and the reporter picks up the rest.
    func waitForFrame(timeout: TimeInterval = SystemSettingsWindowTracker.appearanceTimeout) async -> CGRect? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var previous: CGRect?
        var firstSeen: TimeInterval?

        while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
            if let frame = await Self.scanFrame() {
                let now = ProcessInfo.processInfo.systemUptime
                if let previous, Self.isStable(previous: previous, current: frame) {
                    return frame
                }
                let seenAt = firstSeen ?? now
                firstSeen = seenAt
                previous = frame
                if now - seenAt >= Self.stabilisationBudget {
                    logger.debug("System Settings window did not settle; docking to the latest frame")
                    return frame
                }
            }
            try? await Task.sleep(for: .milliseconds(Int(Self.pollInterval * 1000)))
        }

        if previous == nil {
            logger.error("System Settings window never appeared")
        }
        return previous
    }

    // MARK: - Following

    /// Starts reporting the window's frame (Cocoa points) on every change, and calls `onDisappear`
    /// once the window has been gone for `disappearanceMisses` polls.
    func startReporting() {
        guard reportingTask == nil else { return }
        reportingTask = Task { [weak self] in
            var last: CGRect?
            var misses = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(Self.pollInterval * 1000)))
                guard !Task.isCancelled, let self else { return }
                guard let frame = await Self.scanFrame() else {
                    misses += 1
                    if misses >= Self.disappearanceMisses {
                        self.onDisappear?()
                        return
                    }
                    continue
                }
                misses = 0
                guard frame != last else { continue }
                last = frame
                self.onFrameChange?(frame)
            }
        }
    }

    func stop() {
        reportingTask?.cancel()
        reportingTask = nil
        onFrameChange = nil
        onDisappear = nil
    }

    // MARK: - The live window list

    /// One window-list snapshot, taken off the main actor.
    nonisolated static func scanFrame() async -> CGRect? {
        await Task.detached(priority: .utility) { settingsWindowFrame() }.value
    }

    /// How many System Settings windows are on screen, counted off the main actor.
    nonisolated static func scanWindowCount() async -> Int {
        await Task.detached(priority: .utility) { settingsWindowCount() }.value
    }

    /// The largest layer-0 System Settings window, flipped to Cocoa screen points.
    ///
    /// Largest rather than first: the picker, the Go-to-folder sheet, and the pane's own transient
    /// panels all belong to the same owner, and the main window is the one big enough to hold an app
    /// list. `layer == 0` excludes the menu-bar extras; the size floor excludes tooltips.
    nonisolated static func settingsWindowFrame() -> CGRect? {
        guard let bounds = settingsBounds(from: liveCandidates(), settingsProcessID: settingsProcessID) else { return nil }
        return ScreenGeometryProvider.toCocoa(bounds)
    }

    /// The System Settings process, if it is running.
    ///
    /// Resolved through LaunchServices rather than from the window itself because the window list
    /// only names an owner *locally*: a Chinese system reports 系统设置, a German one
    /// Systemeinstellungen. The bundle identifier does not translate.
    nonisolated static var settingsProcessID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: PermissionPane.settingsBundleIdentifier)
            .first?
            .processIdentifier
    }

    nonisolated static func isSettingsWindow(_ candidate: Candidate, settingsProcessID: pid_t?) -> Bool {
        if let settingsProcessID, candidate.ownerPID == settingsProcessID { return true }
        return PermissionPane.isSettingsOwner(candidate.ownerName)
    }

    nonisolated static func settingsBounds(from candidates: [Candidate], settingsProcessID: pid_t? = nil) -> CGRect? {
        candidates
            .filter { isSettingsWindow($0, settingsProcessID: settingsProcessID) && $0.layer == 0 }
            .filter { $0.bounds.width >= minimumSize.width && $0.bounds.height >= minimumSize.height }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }?
            .bounds
    }

    /// How many System Settings windows are on screen right now.
    ///
    /// Deliberately unfiltered — no layer, no size, no alpha — because the point is to notice a
    /// *drop*: a privacy alert is a sheet inside the window, so the count falls when the decision is
    /// made and the sheet animates away, and that is the only structural signal TCC gives us. The
    /// filtering that keeps a closing tooltip or a pane swap from looking like a dismissal lives in
    /// `TCCGrantWatchState`, which requires the drop to hold for several polls.
    nonisolated static func settingsWindowCount(settingsProcessID: pid_t? = nil) -> Int {
        liveCandidates()
            .filter { isSettingsWindow($0, settingsProcessID: settingsProcessID) }
            .count
    }

    /// Two samples count as settled once they agree to the pixel.
    ///
    /// Rounded for *comparison only*. The frame that goes on to be a dock target is the unrounded
    /// one: a window placed at a sub-point origin must not be reported as somewhere it is not.
    nonisolated static func isStable(previous: CGRect, current: CGRect) -> Bool {
        rounded(previous) == rounded(current)
    }

    nonisolated static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x.rounded(),
            y: rect.origin.y.rounded(),
            width: rect.width.rounded(),
            height: rect.height.rounded()
        )
    }

    nonisolated private static func liveCandidates() -> [Candidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let rawBounds = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary)
            else { return nil }
            return Candidate(ownerName: owner, ownerPID: ownerPID, layer: layer, bounds: bounds)
        }
    }
}
