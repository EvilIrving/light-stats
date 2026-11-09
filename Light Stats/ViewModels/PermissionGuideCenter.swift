//
//  PermissionGuideCenter.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// The one way into the drag-to-grant guide.
///
/// Every permission entry point in the app used to dead-end at "open System Settings": the user
/// landed in a list with no idea that the thing they had to add was *the app they were looking at*,
/// and no way back. This replaces the dead end with the one gesture the pane is built for — drag the
/// app into the list — and then resolves the grant instead of leaving the user to guess.
///
/// The flow, in order: open the pane, wait for its window to appear and settle, fly a card from
/// wherever the user clicked to a slot beside that window, let them drag the app icon into the list,
/// and watch for the grant.
///
/// It is a view model that owns a window — the same arrangement as `UpdateManager` and its update
/// window — because the card has to sit beside *another application's* window, which no SwiftUI
/// window surface offers.
@MainActor
final class PermissionGuideCenter {

    static let shared = PermissionGuideCenter()

    /// Replays the guide from the menu bar without needing a permission to be missing.
    ///
    /// The flow cannot be verified after the fact: on a machine that has already granted the
    /// permission the normal entry points are never reached, and the watcher would conclude on its
    /// first poll. This flag keeps the card up and skips the watcher, so the flight and the dock can
    /// be looked at.
    ///
    /// It is a command-line flag; the Settings row that replays it is `#if DEBUG` only, so no release
    /// UI offers either of them.
    static let replayLaunchArgument = "--permission-guide-demo"

    private let logger = AppLogger(category: "PermissionGuide")
    private var window: PermissionGuideWindow?
    private var tracker: SystemSettingsWindowTracker?
    private var presentTask: Task<Void, Never>?
    /// The presentation the card belongs to. Bumped by every `start`, checked by every completion:
    /// a fade-out that finishes after a new guide began must not tear the new one down.
    private var presentation = 0
    private var anchorFrame: CGRect?
    private var dockedFrame: CGRect?
    private var isReplaying = false
    private var pendingArrival: CheckedContinuation<Void, Never>?

    private init() {}

    var isPresenting: Bool { presentTask != nil }

    // MARK: - Entry points

    func present(pane: PermissionPane, anchor: CGRect?) {
        start(pane: pane, anchor: anchor, replay: false)
    }

    #if DEBUG
    /// Debug only: present without the watcher, so the flight and the dock can be looked at on a
    /// machine that has already granted the permission.
    func presentReplay(pane: PermissionPane, anchor: CGRect?) {
        start(pane: pane, anchor: anchor, replay: true)
    }
    #endif

    /// Called once at launch; does nothing unless the replay flag is on the command line.
    ///
    /// `anchor` is a closure rather than a rectangle because the menu-bar item has no window at the
    /// top of launch, and the flight is supposed to start where the user's click would have been.
    func presentReplayIfRequested(anchor: @escaping @MainActor () -> CGRect?) {
        guard let pane = Self.replayPane else { return }
        Task { [weak self] in
            // The status item is placed in the menu bar a beat after launch.
            try? await Task.sleep(for: .milliseconds(1200))
            // A capability alert can be up at this moment, and it runs a nested run loop: nothing
            // below would progress, and the card would be stranded off the recording. Wait for the
            // developer to answer it.
            for _ in 0..<60 where NSApp.modalWindow != nil {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let self else { return }
            self.start(pane: pane, anchor: anchor(), replay: true)
        }
    }

    private func start(pane: PermissionPane, anchor: CGRect?, replay: Bool) {
        // A card can outlive its task — the relaunch phase waits for the user — so a second entry
        // point replaces what is on screen. Dropping the request on the floor was the worse answer:
        // clicking "Open System Settings" then did nothing at all, with nothing in the journal.
        if presentTask != nil || window != nil {
            DiagnosticLogService.record(category: "permissionGuide", action: "replaced")
        }
        teardown()

        guard let url = pane.url else {
            logger.error("Failed to build a System Settings URL for \(pane.rawValue)")
            return
        }
        presentation &+= 1
        let token = presentation
        isReplaying = replay
        anchorFrame = anchor
        DiagnosticLogService.record(category: "permissionGuide", action: "presented",
                                    fields: ["pane": .publicValue(pane.rawValue),
                                             "anchor": .publicValue(anchor == nil ? "none" : "rect"),
                                             "replay": .publicValue(replay ? "true" : "false")])
        NSWorkspace.shared.open(url)
        presentTask = Task { [weak self] in await self?.run(pane: pane, token: token) }
    }

    // MARK: - The flow

    private func run(pane: PermissionPane, token: Int) async {
        let tracker = SystemSettingsWindowTracker()
        self.tracker = tracker

        guard let settingsFrame = await tracker.waitForFrame(),
              let screen = Self.screen(containing: settingsFrame),
              !Task.isCancelled, token == presentation
        else {
            logger.error("System Settings window never appeared; permission guide stopped")
            return teardown(token: token)
        }

        let dock = PermissionGuideGeometry.dock(
            cardSize: PermissionGuideCardView.cardSize,
            beside: settingsFrame,
            visibleFrame: screen.visibleFrame
        )
        let window = makeWindow(pane: pane, dock: dock)
        self.window = window
        dockedFrame = dock.frame
        await animateIn(window: window, dock: dock)
        guard !Task.isCancelled, token == presentation else { return }

        guard !isReplaying else { return }

        tracker.onFrameChange = { [weak self] frame in self?.follow(frame) }
        tracker.onDisappear = { [weak self] in self?.dismissAnimated() }
        tracker.startReporting()

        let result = await TCCGrantWatcher(readGrant: { Self.isGranted(pane) }).wait()
        guard token == presentation else { return }
        resolve(result, pane: pane)

        // The card can still be on screen (the relaunch phase waits for the user), but this task is
        // finished. Holding it here would make every later `present` a silent no-op for the rest of
        // the session.
        presentTask = nil
    }

    private func makeWindow(pane: PermissionPane,
                            dock: PermissionGuideGeometry.Dock) -> PermissionGuideWindow {
        let state = PermissionGuideCardState(
            pane: pane,
            side: dock.side,
            appName: Self.appName,
            dropBundleURL: AppBundleDropSource.hostBundleURL
        )
        state.onBack = { [weak self] in self?.cancel() }
        let window = PermissionGuideWindow(cardState: state)
        window.move(to: dock.frame)
        return window
    }

    /// The flight from the click to the slot, or a plain fade when there was no click to fly from.
    ///
    /// Reduce Motion shortens the flight rather than removing it: an instant jump reads as a glitch,
    /// a short one still reads as a deliberate movement.
    private func animateIn(window: PermissionGuideWindow, dock: PermissionGuideGeometry.Dock) async {
        guard let anchor = anchorFrame else {
            window.fadeIn(at: dock.frame)
            try? await Task.sleep(for: .milliseconds(240))
            return
        }
        let duration = ReduceMotionPreference.isEnabled
            ? PermissionGuideFlight.reducedDuration
            : PermissionGuideFlight.outwardDuration
        let flight = PermissionGuideFlight(startFrame: anchor, endFrame: dock.frame, duration: duration)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // The arrival is stored, not captured: `teardown` may happen before the flight ends, and
            // a task parked on a continuation nobody resumes blocks `present` for good.
            pendingArrival = continuation
            window.fly(flight) { [weak self] in self?.finishArrival() }
        }
    }

    private func finishArrival() {
        let continuation = pendingArrival
        pendingArrival = nil
        continuation?.resume()
    }

    /// Keeps the card beside the window while the user moves it.
    private func follow(_ settingsFrame: CGRect) {
        guard let window, let screen = Self.screen(containing: settingsFrame) else { return }
        let dock = PermissionGuideGeometry.dock(
            cardSize: PermissionGuideCardView.cardSize,
            beside: settingsFrame,
            visibleFrame: screen.visibleFrame
        )
        guard dock.frame != dockedFrame else { return }
        dockedFrame = dock.frame
        window.cardState.side = dock.side
        window.move(to: dock.frame)
    }

    // MARK: - Outcomes

    private func resolve(_ result: TCCGrantResult, pane: PermissionPane) {
        DiagnosticLogService.record(category: "permissionGuide", action: "resolved",
                                    fields: ["pane": .publicValue(pane.rawValue),
                                             "result": .publicValue(result.diagnosticName)])
        // Nothing below follows the window any more, and the relaunch card can stay up for a long
        // time: polling the window list for a card that no longer moves is pure cost.
        tracker?.stop()

        switch result {
        case .granted:
            toast("permission.guide.granted".localized(pane.displayNameKey.localized),
                  systemImage: "checkmark.circle", tint: .green)
            dismissAnimated()
        case .finishedInSettings where pane == .screenRecording:
            // The guide is the thing that took the user to the pane, so this is the moment the
            // session counts as having been asked — not the moment the card appeared, which would
            // have claimed a restart for a user who pressed Back.
            ScreenRecordingPermission.markRequested()
            showRelaunchRequired()
        case .finishedInSettings, .timedOut:
            // A refusal and a timeout used to look identical: the card flew away and the user was
            // back at the dead end this feature exists to remove.
            logger.info("Permission guide concluded without reading the grant")
            ToastCenter.shared.show(
                message: "permission.guide.notGranted".localized(pane.displayNameKey.localized),
                systemImage: "exclamationmark.triangle",
                tint: .orange,
                duration: 3
            )
            dismissAnimated()
        }
    }

    /// The Screen Recording half of "do not show a bare Done": this process cannot read the grant it
    /// was just given, so the card offers the restart that makes it real.
    ///
    /// The verdict is not made here — `ScreenRecordingAuthorization.resolve` is the one rule, and it
    /// is the same rule the settings row reads.
    private func showRelaunchRequired() {
        guard let window else { return dismissAnimated() }
        guard ScreenRecordingAuthorization.resolve(
            isGranted: ScreenRecordingPermission.isGranted,
            hasRequestedThisSession: ScreenRecordingPermission.hasBeenRequested
        ) == .requiresRestart else {
            // Granted after all: this process can read it, so there is nothing to restart.
            toast("permission.guide.granted".localized(PermissionPane.screenRecording.displayNameKey.localized),
                  systemImage: "checkmark.circle", tint: .green)
            return dismissAnimated()
        }
        window.cardState.phase = .relaunchRequired
        window.cardState.onRelaunch = { [weak self] in
            ApplicationRelaunch.relaunch { [weak self] reason in
                self?.logger.error("Relaunch failed: \(reason)")
                ToastCenter.shared.show(
                    message: "settings.permission.relaunchFailed".localized,
                    systemImage: "exclamationmark.triangle",
                    tint: .orange,
                    duration: 3
                )
            }
        }
    }

    private func toast(_ message: String, systemImage: String, tint: Color) {
        ToastCenter.shared.show(message: message, systemImage: systemImage, tint: tint)
    }

    // MARK: - Cancelling

    /// The back affordance: undo the flight, then let go.
    private func cancel() {
        let token = presentation
        presentTask?.cancel()
        guard let window else { return teardown(token: token) }
        DiagnosticLogService.record(category: "permissionGuide", action: "cancelled")
        guard let anchor = anchorFrame else {
            window.fadeOut { [weak self] in self?.teardown(token: token) }
            return
        }
        window.flyBack(to: anchor) { [weak self] in self?.teardown(token: token) }
    }

    private func dismissAnimated() {
        let token = presentation
        guard let window else { return teardown(token: token) }
        window.fadeOut { [weak self] in self?.teardown(token: token) }
    }

    private func teardown() {
        teardown(token: presentation)
    }

    /// Releases everything the given presentation owns. A completion from an older presentation is
    /// ignored rather than allowed to clear the card in front of the user.
    private func teardown(token: Int) {
        guard token == presentation else { return }
        tracker?.stop()
        tracker = nil
        window?.stopMotion()
        window?.orderOut(nil)
        window = nil
        dockedFrame = nil
        anchorFrame = nil
        isReplaying = false
        presentTask = nil
        finishArrival()
    }

    // MARK: - Values

    private static var appName: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? "Light Stats"
    }

    /// The display the Settings window mostly sits on.
    ///
    /// Never `NSScreen.main`: that is the screen holding *our* key window, which for a menu-bar app
    /// is the menu-bar screen — not necessarily the one the Settings window is on. When the window
    /// momentarily intersects no screen at all (a display arrangement change, or a window dragged
    /// off-screen) the first screen is the deterministic answer, and docking is skipped for that
    /// frame anyway.
    private static func screen(containing frame: CGRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best ?? NSScreen.screens.first
    }

    private static func isGranted(_ pane: PermissionPane) -> Bool {
        switch pane {
        case .accessibility: return AccessibilityPermission.isTrusted()
        case .screenRecording: return ScreenRecordingPermission.isGranted
        }
    }

    private static var replayPane: PermissionPane? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: replayLaunchArgument) else { return nil }
        let valueIndex = arguments.index(after: flag)
        guard valueIndex < arguments.endIndex, let pane = PermissionPane(rawValue: arguments[valueIndex]) else {
            return .accessibility
        }
        return pane
    }
}

// MARK: - Anchoring

/// Reports a view's rectangle in screen coordinates so a button can throw the card from itself.
private struct PermissionGuideAnchorReader: NSViewRepresentable {

    let onChange: @MainActor (CGRect) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = AnchorReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? AnchorReportingView)?.onChange = onChange
        nsView.superview?.needsLayout = true
    }

    private final class AnchorReportingView: NSView {

        var onChange: (@MainActor (CGRect) -> Void)?

        override func layout() {
            super.layout()
            report()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        private func report() {
            guard let window, !bounds.isEmpty else { return }
            onChange?(window.convertToScreen(convert(bounds, to: nil)))
        }
    }
}

extension View {
    /// Supplies the global screen rectangle of this view, for `PermissionGuideCenter.present`.
    func permissionGuideAnchor(_ onChange: @escaping @MainActor (CGRect) -> Void) -> some View {
        background(PermissionGuideAnchorReader(onChange: onChange))
    }
}
