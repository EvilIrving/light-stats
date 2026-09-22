//
//  DockClickService.swift
//  Light Stats
//

import AppKit
import ApplicationServices

/// Turns a click on a Dock icon into "put this app's windows away" / "bring them back".
///
/// Why this exists at all: macOS activates a non-frontmost application when its Dock icon is clicked,
/// and brings a minimized window back, but clicking the *frontmost* app's icon does nothing. That one
/// missing direction is what makes the gesture a toggle, and it is the reason this is not a duplicate
/// of anything the system already does.
///
/// Detection is an `NSEvent` global monitor, not an event tap: a passive monitor needs no permission
/// of its own, cannot swallow an event, and is delivered on the main thread, which is where every
/// decision below is made. The exception is the Accessibility work — resolving the icon and reading
/// the application's window facts — which runs on `AXCommandQueue` like every other AX call here.
///
/// The click is judged on facts captured *before* the mouse went down, because the Dock changes the
/// world while it handles the click: whether the app was frontmost and whether it was showing windows
/// cannot be recovered afterwards.
@MainActor
final class DockClickService {

    private let logger = AppLogger(category: "DockClick")
    private let minimizeService: WindowMinimizeService

    private var monitors: [Any] = []
    private var configuration: SnapConfiguration = .default
    private var isSuspended = false
    private(set) var isRunning = false

    private var gesture = DockClickGesture()
    private var clickGeneration: UInt64 = 0
    private var pendingCandidate: DockClickCandidate?
    private var pendingFacts: WindowMinimizeService.WindowFacts?
    private var upPoint: CGPoint?
    private var upAt: TimeInterval = 0
    private var lastAction: DockClickMoment?

    init(minimizeService: WindowMinimizeService = WindowMinimizeService()) {
        self.minimizeService = minimizeService
    }

    // MARK: - Lifecycle

    func update(configuration: SnapConfiguration) {
        self.configuration = configuration
    }

    /// Starts the click monitors. Returns `false` when Accessibility is missing: minimizing another
    /// application's windows needs it, and a monitor we cannot act on would only add latency.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard AccessibilityPermission.isTrusted(prompt: false) else { return false }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            // Global monitors are delivered on the main thread; the handler has no isolation because
            // AppKit cannot express one.
            MainActor.assumeIsolated { self?.handle(event) }
        }) else {
            logger.error("Failed to install the Dock click monitor")
            return false
        }
        monitors = [monitor]
        isRunning = true
        logger.info("Dock click service started")
        return true
    }

    func stop() {
        guard isRunning else { return }
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        isRunning = false
        reset()
        forgetAll()
        logger.info("Dock click service stopped")
    }

    /// Ignored while one of our own panels is in front, so a file panel is never the reason a window
    /// disappears behind it.
    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        if suspended { reset() }
    }

    /// Drops the "we collapsed these" bookkeeping. The windows stay minimized — putting them back
    /// would be a side effect nobody asked for — and a later click can no longer claim to restore a
    /// set this feature does not own.
    func forgetAll() {
        minimizeService.forgetAll()
    }

    // MARK: - Events

    private func handle(_ event: NSEvent) {
        guard isRunning, !isSuspended, configuration.isDockClickCollapseEnabled else { return }
        let point = ScreenGeometryProvider.toAccessibility(event.locationInWindow)
        let now = ProcessInfo.processInfo.systemUptime

        switch event.type {
        case .leftMouseDown:
            beginClick(at: point, now: now)
        case .leftMouseDragged:
            // A Dock icon drag rearranges the Dock; that is not a click, and its release must not
            // collapse anything.
            if gesture.moved(to: point) {
                clickGeneration &+= 1
                pendingCandidate = nil
                pendingFacts = nil
            }
        case .leftMouseUp:
            upPoint = point
            upAt = now
            evaluateIfReady()
        case .rightMouseDown:
            // The context menu is about to open over the icon; nothing of ours should survive it.
            reset()
        default:
            break
        }
    }

    private func beginClick(at point: CGPoint, now: TimeInterval) {
        reset()
        // Cheap rejection first: a click anywhere but the Dock is the overwhelmingly common case, and
        // it must not cost an Accessibility round trip. The band is derived from the screen's visible
        // frame and the Dock's own preference, so this is arithmetic.
        guard Self.isInsideDockBand(point) else { return }
        gesture.begins(at: point, now: now)
        let generation = clickGeneration

        AXCommandQueue.shared.async { [weak self] in
            let icon = Self.resolveIcon(at: point)
            Task { @MainActor [weak self] in
                self?.iconResolved(icon, generation: generation, at: point)
            }
        }
    }

    /// The second half of the resolution, on the main actor.
    ///
    /// The split is not cosmetic: `NSWorkspace` and `NSRunningApplication` are AppKit, and asking them
    /// from the AX queue returns a stale application list — a running app reads as "not running", which
    /// is how this feature first failed. Only the pure Accessibility work is allowed off-main.
    private func iconResolved(_ icon: DockIcon?, generation: UInt64, at point: CGPoint) {
        guard clickGeneration == generation, gesture.isPending else { return }
        guard let icon else {
            recordUnresolvedClick(at: point)
            return
        }
        let application = NSWorkspace.shared.runningApplications.first { running in
            running.bundleIdentifier == icon.bundleIdentifier && running.activationPolicy == .regular
        }
        let processID = application?.processIdentifier ?? 0
        let minimizeService = self.minimizeService
        AXCommandQueue.shared.async { [weak self] in
            let facts = processID == 0
                ? WindowMinimizeService.WindowFacts(
                    hasVisibleWindows: false, hasCollapsibleWindows: false, hasMinimizedWindows: false, focusedTitle: nil
                )
                : minimizeService.windowFacts(processID: processID)
            Task { @MainActor [weak self] in
                guard let self, self.clickGeneration == generation, self.gesture.isPending else { return }
                self.pendingFacts = facts
                self.pendingCandidate = DockClickCandidate(
                    processID: processID,
                    bundleIdentifier: icon.bundleIdentifier,
                    name: application?.localizedName ?? icon.name,
                    isOwnApplication: processID == ProcessInfo.processInfo.processIdentifier,
                    isRunning: application != nil,
                    isRegular: application?.activationPolicy == .regular,
                    wasFrontmost: application?.isActive ?? false,
                    hasVisibleWindows: facts.hasVisibleWindows,
                    hasCollapsibleWindows: facts.hasCollapsibleWindows,
                    hasMinimizedWindows: facts.hasMinimizedWindows
                )
                self.evaluateIfReady()
            }
        }
    }

    /// Runs when both halves of the click are known: the button came up, and the icon underneath has
    /// been resolved. A fast click can finish before the AX tree answers, so this is called from both
    /// paths and does nothing until both are present.
    private func evaluateIfReady() {
        guard gesture.isPending, let upPoint, let candidate = pendingCandidate else { return }
        guard gesture.ends(at: upPoint, now: upAt) else { return }
        guard let facts = pendingFacts else { return }

        let now = ProcessInfo.processInfo.systemUptime
        clickGeneration &+= 1
        self.pendingCandidate = nil
        self.pendingFacts = nil

        guard !DockClickPolicy.isRepeat(since: lastAction, processID: candidate.processID, at: now) else {
            return
        }
        let collapsedByUs = minimizeService.recordExists(for: candidate.processID)
        switch DockClickPolicy.action(for: candidate, isCollapsedByUs: collapsedByUs) {
        case .pass(let reason):
            // Silence on purpose: this runs for every Dock click in the system, and a journal that
            // records ordinary clicks would hide the faults it exists to show.
            if reason == "windows-away" {
                // The windows are gone from Accessibility and the Dock is restoring them itself; the
                // record has nothing left to own.
                minimizeService.forget(processID: candidate.processID)
            }
            logger.debug("Dock click ignored: \(reason) app=\(candidate.name)")
        case .collapse(let processID):
            perform(collapse: true, processID: processID, candidate: candidate, facts: facts, now: now)
        case .restore(let processID):
            perform(collapse: false, processID: processID, candidate: candidate, facts: facts, now: now)
        }
    }

    private func perform(
        collapse: Bool,
        processID: pid_t,
        candidate: DockClickCandidate,
        facts: WindowMinimizeService.WindowFacts,
        now: TimeInterval
    ) {
        let minimizeService = self.minimizeService
        AXCommandQueue.shared.async {
            let outcome = collapse
                ? minimizeService.collapse(processID: processID, facts: facts)
                : minimizeService.restore(processID: processID)
            Task { @MainActor [weak self] in
                self?.finish(collapse: collapse, outcome: outcome, candidate: candidate, startedAt: now)
            }
        }
    }

    private func finish(
        collapse: Bool,
        outcome: WindowMinimizeService.Outcome,
        candidate: DockClickCandidate,
        startedAt: TimeInterval
    ) {
        let duration = ProcessInfo.processInfo.systemUptime - startedAt
        let fields: [String: String] = [
            "app": candidate.bundleIdentifier ?? candidate.name,
            "changed": String(outcome.changed),
            "attempted": String(outcome.attempted),
            "durationMS": String(format: "%.1f", duration * 1000),
            "reasonCode": outcome.reason
        ]

        // A wave that changed nothing is a failure, not a toggle: forget it, so the next click starts
        // from the truth instead of believing a set is collapsed.
        guard outcome.changed > 0 else {
            minimizeService.forget(processID: candidate.processID)
            DiagnosticLogService.record(
                category: "dockClick",
                action: collapse ? "collapseFailed" : "restoreFailed",
                fields: fields
            )
            return
        }
        lastAction = DockClickMoment(processID: candidate.processID, at: ProcessInfo.processInfo.systemUptime)
        DiagnosticLogService.record(category: "dockClick", action: collapse ? "collapsed" : "restored", fields: fields)
    }

    private func reset() {
        gesture.cancel()
        pendingCandidate = nil
        pendingFacts = nil
        upPoint = nil
        upAt = 0
    }

    // MARK: - Resolving the Dock icon

    /// What the Dock's Accessibility surface says about the icon under a point. Everything here is
    /// readable without AppKit, which is what lets the whole lookup run on the AX queue.
    nonisolated private struct DockIcon: Sendable {
        var bundleIdentifier: String
        var name: String
    }

    /// Finds the application icon under a point. Runs on the AX queue; no AppKit.
    nonisolated private static func resolveIcon(at point: CGPoint) -> DockIcon? {
        // One of our own panels can sit inside the Dock's band. Asking Accessibility about that point
        // is answered on this thread, where AppKit's Accessibility entry points may not run.
        guard !OwnSurfaceHitTest.wouldResolveOwnUI(at: point) else { return nil }
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(point.x),
            Float(point.y),
            &element
        ) == .success, let element, let item = dockItem(from: element) else {
            return nil
        }
        guard let url = dockItemURL(item),
              let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else { return nil }
        let title: String? = AXElementReader.attribute(kAXTitleAttribute, from: item)
        return DockIcon(
            bundleIdentifier: bundleIdentifier,
            name: title ?? url.deletingPathExtension().lastPathComponent
        )
    }

    /// Walks up from the element under the pointer to the Dock's application item.
    ///
    /// The climb is bounded and every step must still belong to the Dock process: an element that is
    /// not a Dock icon (the Trash, a stack, the empty Dock background) must not resolve to whatever
    /// happens to sit above it.
    nonisolated private static func dockItem(from element: AXUIElement) -> AXUIElement? {
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier else { return nil }
        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let candidate = current else { return nil }
            guard AXElementReader.processIdentifier(of: candidate) == dockPID else { return nil }
            let subrole: String? = AXElementReader.attribute(kAXSubroleAttribute, from: candidate)
            if subrole == "AXApplicationDockItem" { return candidate }
            current = AXElementReader.attribute(kAXParentAttribute, from: candidate)
        }
        return nil
    }

    nonisolated private static func dockItemURL(_ item: AXUIElement) -> URL? {
        guard let raw: CFTypeRef = AXElementReader.attribute("AXURL", from: item) else { return nil }
        if let url = raw as? URL { return url }
        // The Dock has historically returned the URL as a string on some releases.
        if let string = raw as? String { return URL(string: string) }
        return nil
    }

    /// Whether a point in Accessibility space lies in the Dock's band on its screen.
    ///
    /// The slack is wider than the hover monitor's: an icon under the pointer magnifies, and the
    /// click that lands on its edge is still a click on that icon.
    private static func isInsideDockBand(_ point: CGPoint, slack: CGFloat = 10) -> Bool {
        guard let screen = ScreenGeometryProvider.screen(containing: point) else { return false }
        let band = DockGeometry.band(
            screen: ScreenGeometryProvider.toCocoa(screen.frame),
            visibleFrame: ScreenGeometryProvider.toCocoa(screen.visibleFrame),
            orientation: DockHoverMonitorService.dockOrientation(),
            fallbackDockFrame: nil
        )
        let cocoaPoint = CGPoint(x: point.x, y: ScreenGeometryProvider.flipReferenceMaxY() - point.y)
        return DockGeometry.isWithinDock(cocoaPoint, band: band, slack: slack)
    }

    /// A click inside the Dock's band that resolved to no icon. Worth one debug line: it is the signal
    /// that the Dock's Accessibility surface changed shape.
    private func recordUnresolvedClick(at point: CGPoint) {
        guard let screen = ScreenGeometryProvider.screen(containing: point) else { return }
        let band = DockGeometry.band(
            screen: ScreenGeometryProvider.toCocoa(screen.frame),
            visibleFrame: ScreenGeometryProvider.toCocoa(screen.visibleFrame),
            orientation: DockHoverMonitorService.dockOrientation(),
            fallbackDockFrame: nil
        )
        DiagnosticLogService.recordPrivate(
            level: .debug,
            category: "dockClick",
            action: "unresolvedIcon",
            fields: ["bandHeight": String(format: "%.0f", band.height)]
        )
    }
}
