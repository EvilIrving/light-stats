//
//  DockHoverMonitorService.swift
//  Light Stats
//

import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

/// The Dock icon under the pointer.
nonisolated struct DockHoverTarget: @unchecked Sendable, Equatable {
    var processID: pid_t
    var appName: String
    var bundleIdentifier: String?
    /// The Dock item's rect, in Cocoa coordinates.
    var itemFrame: CGRect

    static func == (lhs: DockHoverTarget, rhs: DockHoverTarget) -> Bool {
        lhs.processID == rhs.processID && lhs.itemFrame == rhs.itemFrame
    }
}

protocol DockHoverMonitoring: AnyObject {
    var isRunning: Bool { get }
    /// A Dock icon has been hovered long enough to preview.
    var onHover: ((DockHoverTarget) -> Void)? { get set }
    /// The pointer has settled on an icon that is not being previewed yet — the moment to warm its
    /// thumbnails, so the panel that follows arrives with pictures.
    var onWarm: ((DockHoverTarget) -> Void)? { get set }
    /// The pointer left both the Dock and the preview panel.
    var onExit: (() -> Void)? { get set }
    /// The panel the controller is currently showing, so hovering *it* does not count as leaving.
    var previewFrame: CGRect? { get set }
    /// Whether the pointer is resting on this application's icon.
    func isHovering(_ processID: pid_t) -> Bool
    func start() -> Bool
    func stop()
    func setSuspended(_ suspended: Bool)
}

/// Watches the pointer for a hover over a Dock icon.
///
/// Polls rather than tapping `mouseMoved`. A move-event tap fires on every pixel of travel — on a
/// 120 Hz trackpad that is thousands of events a second, all to answer a question that changes at
/// human speed. A 12 Hz poll of the pointer position costs nothing and only reaches for
/// Accessibility when the pointer is actually inside the Dock's rectangle.
///
/// The hovered icon is resolved through Accessibility rather than by guessing from the pointer's x
/// position against the Dock's icon grid: Dock magnification, spacers, stacks, and folders all break
/// the arithmetic, and `AXApplicationDockItem` is the Dock's own answer to "which icon is this".
nonisolated final class DockHoverMonitorService: DockHoverMonitoring, @unchecked Sendable {

    private let logger = AppLogger(category: "DockPreview")
    private let stateLock = NSLock()

    private var timer: DispatchSourceTimer?
    private var running = false
    private var suspended = false

    /// The icon the pointer is resting on and how long it has been there — a preview that appears
    /// the instant the pointer crosses an icon is noise while the user is just travelling along the
    /// Dock. Moving to another icon restarts this; it does not dismiss the panel.
    private var hover = DockHoverPolicy.State.idle
    /// The icon whose preview is on screen.
    private var presented: DockHoverTarget?
    private var retention = DockPreviewRetention()
    /// Cache of Dock item element → resolved target, so walking the AX tree and reading the bundle
    /// identifier happens once per icon rather than once per poll.
    private var itemCache: [UInt: DockHoverTarget] = [:]

    private let pollInterval: TimeInterval = 1.0 / 30
    /// How far outside the Dock's rectangle still counts as hovering it.
    private let dockSlack: CGFloat = 6

    var onHover: ((DockHoverTarget) -> Void)?
    var onWarm: ((DockHoverTarget) -> Void)?
    var onExit: (() -> Void)?

    var previewFrame: CGRect? {
        get {
            stateLock.lock(); defer { stateLock.unlock() }
            return presentedPreviewFrame
        }
        set {
            stateLock.lock()
            presentedPreviewFrame = newValue
            stateLock.unlock()
        }
    }
    private var presentedPreviewFrame: CGRect?
    private var previousProbe: (point: CGPoint, target: DockHoverTarget?, band: CGRect, time: TimeInterval)?

    /// Injected so tests can drive the decision without a Dock.
    var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }
    /// Injected so tests can supply a fake Dock.
    lazy var dockProbe: (CGPoint) -> (target: DockHoverTarget?, band: CGRect)? = { [weak self] point in
        self?.probeSystemDock(at: point)
    }
    /// Injected so tests can advance the clock instead of waiting for it.
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    /// Whether the pointer is resting on this application's icon.
    ///
    /// Deliberately about the icon under the pointer rather than about the panel on screen: while
    /// the pointer travels from one icon to the next the panel still holds the previous
    /// application, and a preview that is about to be replaced must not be read as "not hovering
    /// any more".
    func isHovering(_ processID: pid_t) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running && !suspended && hover.candidate?.processID == processID
    }

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    // MARK: - Lifecycle

    func start() -> Bool {
        guard !isRunning else { return true }
        guard AccessibilityPermission.isTrusted() else {
            logger.debug("Dock preview needs Accessibility to read the Dock's items")
            return false
        }

        stateLock.lock()
        running = true
        hover = .idle
        presented = nil
        stateLock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(
            label: "com.lightstats.dock-hover",
            qos: .utility
        ))
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        logger.info("Dock hover monitor started")
        return true
    }

    func stop() {
        stateLock.lock()
        guard running else { stateLock.unlock(); return }
        running = false
        hover = .idle
        presented = nil
        presentedPreviewFrame = nil
        previousProbe = nil
        itemCache.removeAll()
        stateLock.unlock()

        timer?.cancel()
        timer = nil
        logger.info("Dock hover monitor stopped")
    }

    func setSuspended(_ suspended: Bool) {
        stateLock.lock()
        self.suspended = suspended
        if suspended {
            hover = .idle
            presented = nil
        }
        stateLock.unlock()
        if suspended {
            notifyExit()
        }
    }

    // MARK: - Poll

    private func tick() {
        stateLock.lock()
        let isSuspended = suspended
        let isRunning = running
        stateLock.unlock()
        guard isRunning, !isSuspended else { return }

        let point = pointerLocation()
        let now = clock()
        if let frame = previewFrame, frame.contains(point) {
            stateLock.lock()
            retention.visit(at: now)
            stateLock.unlock()
            return
        }
        guard let probe = cachedProbe(at: point, time: now) else {
            resolveExit()
            return
        }

        guard let target = probe.target, DockGeometry.isWithinDock(point, band: probe.band, slack: dockSlack) else {
            resolveExit()
            return
        }

        stateLock.lock()
        retention.visit(at: now)
        let action = DockHoverPolicy.settled(&hover, presented: presented, target: target, now: now)
        if case .show(let shown) = action { presented = shown }
        stateLock.unlock()

        switch action {
        case .idle:
            break
        case .warm(let warmed):
            notify(onWarm, with: warmed)
        case .show(let shown):
            logger.debug("Dock hover preview for \(shown.appName)")
            notify(onHover, with: shown)
        }
    }

    /// Delivers a hover callback on the main actor, where every consumer lives.
    private func notify(_ callback: ((DockHoverTarget) -> Void)?, with target: DockHoverTarget) {
        guard let callback else { return }
        Task { @MainActor in
            callback(target)
        }
    }

    private func cachedProbe(at point: CGPoint, time: TimeInterval) -> (target: DockHoverTarget?, band: CGRect)? {
        stateLock.lock()
        let previous = previousProbe
        stateLock.unlock()
        if let previous, hypot(point.x - previous.point.x, point.y - previous.point.y) < 1,
           time - previous.time < 0.25 {
            return (previous.target, previous.band)
        }
        let result = AXCommandQueue.shared.sync { dockProbe(point) }
        stateLock.lock()
        previousProbe = result.map { (point, $0.target, $0.band, time) }
        stateLock.unlock()
        return result
    }

    private func resolveExit() {
        stateLock.lock()
        guard presented == nil || retention.shouldDismiss(at: clock()) else {
            stateLock.unlock()
            return
        }
        let hadPresented = presented != nil
        hover = .idle
        presented = nil
        retention.reset()
        stateLock.unlock()
        if hadPresented {
            notifyExit()
        }
    }

    private func notifyExit() {
        let callback = onExit
        Task { @MainActor in
            callback?()
        }
    }

    // MARK: - The real Dock

    /// Resolves the Dock item under a point, plus the Dock's own rectangle.
    ///
    /// Runs on the polling queue. It only does Accessibility work when the pointer is inside the
    /// Dock's region, so a pointer anywhere else on screen costs one `NSScreen` read.
    private func probeSystemDock(at point: CGPoint) -> (target: DockHoverTarget?, band: CGRect)? {
        guard let screen = screenContaining(cocoaPoint: point) else { return nil }
        let orientation = Self.dockOrientation()
        let estimatedBand = DockGeometry.band(
            screen: screen.frame, visibleFrame: screen.visibleFrame, orientation: orientation, fallbackDockFrame: nil
        )
        guard DockGeometry.isWithinDock(point, band: estimatedBand, slack: dockSlack) else {
            return (nil, estimatedBand)
        }
        let dockFrame = dockAccessibilityFrame()
        let band = DockGeometry.band(
            screen: screen.frame,
            visibleFrame: screen.visibleFrame,
            orientation: orientation,
            fallbackDockFrame: dockFrame
        )
        guard !band.isEmpty else { return nil }

        // Outside the Dock band there is nothing to resolve, and no reason to walk the AX tree.
        guard DockGeometry.isWithinDock(point, band: band, slack: dockSlack) else {
            return (nil, band)
        }
        // But only inside the *icon row*: below it is the Trash and the empty Dock background, whose
        // AX element is not an application item.
        guard let item = applicationDockItem(at: point) else { return (nil, band) }

        let key = CFHash(item)
        stateLock.lock()
        let cached = itemCache[key]
        stateLock.unlock()
        if let cached, let app = NSRunningApplication(processIdentifier: cached.processID), !app.isTerminated {
            return (DockHoverTarget(
                processID: cached.processID,
                appName: cached.appName,
                bundleIdentifier: cached.bundleIdentifier,
                itemFrame: itemFrame(of: item) ?? cached.itemFrame
            ), band)
        }

        guard let resolved = resolve(item: item) else { return (nil, band) }
        stateLock.lock()
        // Bounded: the Dock's icon set is small, but a stale entry per window title would grow.
        if itemCache.count > 64 { itemCache.removeAll() }
        itemCache[key] = resolved
        stateLock.unlock()
        return (resolved, band)
    }

    /// Walks up from the element under the pointer to the Dock application item that owns it.
    private func applicationDockItem(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let axPoint = ScreenGeometryProvider.toAccessibility(point)
        // One of our own panels can sit inside the Dock band. Asking Accessibility about it would be
        // answered on this thread, where AppKit's Accessibility entry points may not run.
        guard !OwnSurfaceHitTest.wouldResolveOwnUI(at: axPoint) else { return nil }
        guard AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(axPoint.x),
            Float(axPoint.y),
            &element
        ) == .success, let element else {
            return nil
        }

        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let candidate = current else { return nil }
            guard let processID = AXElementReader.processIdentifier(of: candidate),
                  let dockPID = Self.dockProcessIdentifier(),
                  processID == dockPID else {
                // Climbed out of the Dock process — this is not a Dock icon at all.
                return nil
            }
            let subrole: String? = AXElementReader.attribute(kAXSubroleAttribute, from: candidate)
            if subrole == "AXApplicationDockItem" { return candidate }
            current = AXElementReader.attribute(kAXParentAttribute, from: candidate)
        }
        return nil
    }

    private func resolve(item: AXUIElement) -> DockHoverTarget? {
        guard let url = dockItemURL(item) else { return nil }
        let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
        guard let bundleIdentifier else { return nil }
        guard let application = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleIdentifier && $0.activationPolicy == .regular }) else {
            // The icon exists but the app is not running; there are no windows to preview.
            return nil
        }
        return DockHoverTarget(
            processID: application.processIdentifier,
            appName: application.localizedName ?? url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundleIdentifier,
            itemFrame: itemFrame(of: item) ?? .zero
        )
    }

    private func dockItemURL(_ item: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, "AXURL" as CFString, &value) == .success,
              let raw = value else {
            return nil
        }
        if let url = raw as? URL { return url }
        // The Dock has historically returned the URL as a string on some releases.
        if let string = raw as? String { return URL(string: string) }
        return nil
    }

    private func itemFrame(of item: AXUIElement) -> CGRect? {
        guard let axFrame = AXElementReader.frame(of: item) else { return nil }
        return ScreenGeometryProvider.toCocoa(axFrame)
    }

    /// The Dock's own rectangle, in Cocoa coordinates.
    ///
    /// Needed because an auto-hidden Dock reserves no visible-frame space. While it is revealed —
    /// which is exactly when a hover can happen — its AX list reports a real frame.
    private func dockAccessibilityFrame() -> CGRect? {
        guard let dockPID = Self.dockProcessIdentifier() else { return nil }
        let dock = AXUIElementCreateApplication(dockPID)
        guard let list: AXUIElement = firstElement(in: dock, matching: { element in
            let role: String? = AXElementReader.attribute(kAXRoleAttribute, from: element)
            return role == "AXList"
        }) else {
            return nil
        }
        guard let axFrame = AXElementReader.frame(of: list) else { return nil }
        return ScreenGeometryProvider.toCocoa(axFrame)
    }

    private func firstElement(in root: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue: [AXUIElement] = AXElementReader.elements(kAXChildrenAttribute, from: root)
        var visited = 0
        while !queue.isEmpty, visited < 200 {
            let element = queue.removeFirst()
            visited += 1
            if predicate(element) { return element }
            queue.append(contentsOf: AXElementReader.elements(kAXChildrenAttribute, from: element))
        }
        return nil
    }

    private func screenContaining(cocoaPoint: CGPoint) -> SnapScreenGeometry? {
        guard let screen = ScreenGeometryProvider.screen(containing: ScreenGeometryProvider.toAccessibility(cocoaPoint)) else { return nil }
        return SnapScreenGeometry(
            frame: ScreenGeometryProvider.toCocoa(screen.frame),
            visibleFrame: ScreenGeometryProvider.toCocoa(screen.visibleFrame)
        )
    }

    // MARK: - Dock preferences

    /// The Dock's edge, from `com.apple.dock`. Defaults to the bottom when unset, which is macOS'
    /// own default.
    static func dockOrientation(defaults: UserDefaults = UserDefaults(suiteName: "com.apple.dock") ?? .standard) -> DockOrientation {
        let raw = defaults.string(forKey: "orientation") ?? DockOrientation.bottom.rawValue
        return DockOrientation(rawValue: raw) ?? .bottom
    }

    private static func dockProcessIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }
}
