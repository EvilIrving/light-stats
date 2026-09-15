//
//  WindowDragMonitorService.swift
//  Light Stats
//

import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

/// A window that is currently being dragged.
///
/// `AXUIElement` is a Core Foundation type: immutable, safe to read from any thread, and not
/// `Sendable` as far as the compiler is concerned. Wrapping it states the intent — the element is
/// passed between the tap thread and the main actor, and neither of them mutates it.
nonisolated struct DraggedWindow: @unchecked Sendable {
    var element: AXUIElement
    var processID: pid_t
}

/// One reading of the drag, delivered to the main actor.
nonisolated struct WindowDragState: @unchecked Sendable {
    /// A window is actually being moved. Text selection, resizing, and clicking do not count.
    var isMoving: Bool
    var zone: SnapZoneResult
    /// Where the pointer is, in Accessibility space — the island hit-tests against this.
    var pointer: CGPoint
    /// The dragged window's frame as last sampled. Used as the origin the footprint grows from.
    var windowFrame: CGRect?
    var draggedWindow: DraggedWindow?

    static let idle = WindowDragState(
        isMoving: false,
        zone: .none,
        pointer: .zero,
        windowFrame: nil,
        draggedWindow: nil
    )
}

protocol WindowDragMonitoring: AnyObject {
    var isRunning: Bool { get }
    /// A drag is in progress; called on the main actor.
    var onUpdate: ((WindowDragState) -> Void)? { get set }
    /// A move ended. The main-actor controller resolves island hit-testing before edge fallback.
    var onDrop: ((WindowDragState) -> Void)? { get set }
    /// A drag ended with nothing armed.
    var onCancel: (() -> Void)? { get set }
    /// The dragged window was shaken sideways.
    var onShake: ((DraggedWindow) -> Void)? { get set }
    func start() -> Bool
    func stop()
    func setSuspended(_ suspended: Bool)
    func update(configuration: SnapConfiguration)
}

/// Watches the mouse for window drags and reports which screen edge the drag is arming.
///
/// This is the entry point the product was missing entirely: dragging a window to a screen edge is
/// the one snap gesture everybody already knows, and previously the only way to reach the engine
/// was to know that a two-finger swipe on a titlebar does something.
///
/// Three things keep it from becoming a performance problem:
///
/// - the tap is **listen-only**, so it can never swallow an event or slow the event stream down;
/// - edges and corners are decided from the **pointer**, which is already in the event, so no
///   Accessibility call happens per mouse event;
/// - the only AX work is resolving the dragged window once per drag and reading its frame at
///   roughly 15 Hz, both on the shared serial AX queue, never on the tap thread.
///
/// A drag only counts once the window's own frame has moved. That single test is what separates
/// moving a window from selecting text, resizing it, or clicking inside it — and it is why no
/// titlebar heuristic is needed here at all.
nonisolated final class WindowDragMonitorService: WindowDragMonitoring, @unchecked Sendable {

    private struct DragState {
        var downPoint: CGPoint?
        var window: DraggedWindow?
        var initialFrame: CGRect?
        var isMoving = false
        var isResizing = false
        var lastZone: SnapZoneResult = .none
        var lastPointerSample: TimeInterval = 0
        var lastFrameSample: TimeInterval = 0
        var frameSamplePending = false
        var resolveAttempts = 0
        var lastResolveAt: TimeInterval = 0
        var lastPoint: CGPoint?
        var lastFrame: CGRect?
        var lastPublishedPoint: CGPoint?
    }

    private let logger = AppLogger(category: "WindowDrag")
    private let stateLock = NSLock()
    private let configurationBox = SnapConfigurationBox()

    private var running = false
    private var suspended = false
    private var dragState = DragState()
    private var generation: UInt64 = 0
    private var shakeDetector = DragShakeDetector()

    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Pointer sampling interval. Every event is cheap, but the zone only changes at a rate a person
    /// can perceive, so there is no reason to recompute it faster than this.
    private let pointerSampleInterval: TimeInterval = 1.0 / 60
    /// Frame sampling interval. This is the only expensive call in the loop.
    private let frameSampleInterval: TimeInterval = 1.0 / 30
    /// Movement below this is noise from a click, not a drag.
    private let activationDistance: CGFloat = 4
    /// Below this the window has not really moved.
    private let movementTolerance: CGFloat = 2
    /// How many times to look for the dragged window before accepting that there is not one.
    private let maximumResolveAttempts = 5
    /// Gap between those attempts.
    private let resolveRetryInterval: TimeInterval = 0.08

    var onUpdate: ((WindowDragState) -> Void)?
    var onDrop: ((WindowDragState) -> Void)?
    var onCancel: (() -> Void)?
    var onShake: ((DraggedWindow) -> Void)?

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    func update(configuration: SnapConfiguration) {
        configurationBox.update(configuration)
    }

    // MARK: - Lifecycle

    func start() -> Bool {
        guard !isRunning else { return true }
        guard AccessibilityPermission.isTrusted(prompt: false) else { return false }

        stateLock.lock()
        dragState = DragState()
        running = true
        stateLock.unlock()

        let thread = Thread { [weak self] in self?.runTapLoop() }
        thread.name = "com.lightstats.window-drag-monitor"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        return true
    }

    func stop() {
        stateLock.lock()
        guard running else { stateLock.unlock(); return }
        running = false
        generation &+= 1
        dragState = DragState()
        let loop = tapRunLoop
        stateLock.unlock()

        if let loop {
            CFRunLoopStop(loop)
        }
        tapThread = nil
        publish(.idle)
    }

    /// Temporarily ignores drags — used while one of our own panels is open or a sheet is up.
    func setSuspended(_ suspended: Bool) {
        stateLock.lock()
        self.suspended = suspended
        if suspended {
            generation &+= 1
            dragState = DragState()
        }
        stateLock.unlock()
        if suspended { publish(.idle) }
    }

    // MARK: - Tap

    private func runTapLoop() {
        guard let (tap, source) = makeTap() else {
            stateLock.lock()
            running = false
            stateLock.unlock()
            return
        }

        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        stateLock.lock()
        tapRunLoop = runLoop
        stateLock.unlock()
        logger.info("Window drag monitor started")

        while isRunning {
            let result = CFRunLoopRunInMode(.defaultMode, 1.0e10, false)
            if result == .stopped { break }
        }

        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        eventTap = nil
        runLoopSource = nil
        stateLock.lock()
        tapRunLoop = nil
        stateLock.unlock()
        logger.info("Window drag monitor stopped")
    }

    private func makeTap() -> (CFMachPort, CFRunLoopSource)? {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<WindowDragMonitorService>.fromOpaque(refcon).takeUnretainedValue()
            service.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Failed to create window drag event tap")
            return nil
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("Failed to create run loop source for window drag tap")
            return nil
        }
        return (tap, source)
    }

    // MARK: - Events

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelDrag()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        stateLock.lock()
        let isSuspended = suspended
        let isRunning = running
        stateLock.unlock()
        guard isRunning, !isSuspended else { return }

        // `CGEvent.location` is already in the top-left-origin coordinate system Accessibility uses
        // — unlike `NSEvent.mouseLocation`, which is Cocoa. Flipping it here would mirror every
        // gesture vertically.
        let point = event.location

        switch type {
        case .leftMouseDown:
            beginDrag(at: point)
        case .leftMouseDragged:
            continueDrag(at: point)
        case .leftMouseUp:
            endDrag(at: point)
        default:
            break
        }
    }

    private func beginDrag(at point: CGPoint) {
        stateLock.lock()
        generation &+= 1
        dragState = DragState(downPoint: point)
        shakeDetector.reset()
        stateLock.unlock()
        resolveWindow(at: point)
    }

    private func continueDrag(at point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime

        stateLock.lock()
        guard let downPoint = dragState.downPoint else {
            stateLock.unlock()
            return
        }
        guard hypot(point.x - downPoint.x, point.y - downPoint.y) >= activationDistance else {
            stateLock.unlock()
            return
        }
        // Wins keeps `windowIdAttempt` + `lastWindowIdAttempt` for the same reason: at mouse-down
        // the Accessibility tree frequently has not caught up with the window under the cursor, and
        // one failed lookup used to mean the whole drag was ignored. Bounded rather than open-ended,
        // so a drag across empty desktop costs a handful of hit tests and then stops.
        let shouldResolve = dragState.window == nil
            && dragState.resolveAttempts < self.maximumResolveAttempts
            && now - dragState.lastResolveAt >= self.resolveRetryInterval
        if shouldResolve {
            dragState.resolveAttempts += 1
            dragState.lastResolveAt = now
        }
        let shouldSamplePointer = now - dragState.lastPointerSample >= pointerSampleInterval
        if shouldSamplePointer { dragState.lastPointerSample = now }
        let shouldSampleFrame = dragState.window != nil && !dragState.frameSamplePending
            && now - dragState.lastFrameSample >= frameSampleInterval
        if shouldSampleFrame {
            dragState.lastFrameSample = now
            dragState.frameSamplePending = true
        }
        let previousPoint = dragState.lastPoint
        dragState.lastPoint = point
        let window = dragState.window
        let isMoving = dragState.isMoving
        stateLock.unlock()

        if shouldResolve {
            resolveWindow(at: downPoint)
        }
        // Pointer work first: it is pure arithmetic, and it is what actually decides the zone.
        if shouldSamplePointer {
            updateZone(pointer: point, window: window)
        }
        // Frame work second, and only when a window is known. This is what proves the gesture is a
        // window move rather than a selection or a resize.
        if let window, shouldSampleFrame {
            sampleFrame(for: window)
        }
        if isMoving, let window, let previousPoint, configurationBox.current().isShakeToHideEnabled {
            detectShake(from: previousPoint, to: point, window: window, at: now)
        }
    }

    /// Feeds the shake detector and reports a completed shake.
    ///
    /// Only the horizontal component matters; a vertical shake is not the gesture, and feeding both
    /// would let a fast drag up the screen accumulate reversals.
    private func detectShake(from previous: CGPoint, to current: CGPoint, window: DraggedWindow, at time: TimeInterval) {
        if shakeDetector.update(horizontalDelta: current.x - previous.x, at: time) {
            let token = currentGeneration()
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(token) else { return }
                self.onShake?(window)
            }
        }
    }

    private func endDrag(at point: CGPoint) {
        let configuration = configurationBox.current()
        stateLock.lock()
        let previousZone = dragState.lastZone
        stateLock.unlock()
        let zone = ScreenGeometryProvider.screen(containing: point).map {
            SnapZonePolicy.result(pointer: point, screen: $0, configuration: configuration.effectiveZones, previous: previousZone)
        } ?? .none
        stateLock.lock()
        let state = dragState
        generation &+= 1
        let token = generation
        dragState = DragState()
        stateLock.unlock()
        shakeDetector.reset()

        guard state.downPoint != nil else { return }
        let drop = WindowDragState(
            isMoving: state.isMoving && !state.isResizing,
            zone: zone,
            pointer: point,
            windowFrame: state.lastFrame,
            draggedWindow: state.window
        )
        Task { @MainActor [weak self] in
            guard let self, self.isCurrent(token) else { return }
            if drop.isMoving, drop.draggedWindow != nil {
                self.onDrop?(drop)
            } else {
                self.onCancel?()
            }
            self.onUpdate?(.idle)
        }
    }

    private func cancelDrag() {
        stateLock.lock()
        let hadWindow = dragState.window != nil
        generation &+= 1
        dragState = DragState()
        stateLock.unlock()
        if hadWindow { notifyCancel() }
        publish(.idle)
    }

    private func notifyCancel() {
        let token = currentGeneration()
        Task { @MainActor [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.onCancel?()
        }
    }

    // MARK: - Accessibility work

    /// Resolves the window under the mouse-down point, off the tap thread.
    ///
    /// Resolving at the *down* point rather than at the current pointer position is deliberate: once
    /// the window starts moving, the pointer may be over the desktop or over another app entirely.
    private func resolveWindow(at point: CGPoint) {
        let token = currentGeneration()
        let requestedAt = ProcessInfo.processInfo.systemUptime
        AXCommandQueue.shared.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            let configuration = self.configurationBox.current()

            var element: AXUIElement?
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.08)
            let error = AXUIElementCopyElementAtPosition(
                system,
                Float(point.x),
                Float(point.y),
                &element
            )
            let hitWindow = error == .success ? element.flatMap { Self.windowElement(from: $0) } : nil
            guard let window = hitWindow ?? Self.windowFromServer(at: point),
                  let processID = AXElementReader.processIdentifier(of: window) else { return }
            // Never act on our own windows.
            guard processID != ProcessInfo.processInfo.processIdentifier else { return }

            AXUIElementSetMessagingTimeout(window, 0.06)
            let isFullScreen: Bool? = AXElementReader.attribute("AXFullScreen", from: window)
            let candidate = SnapWindowCandidate(
                role: AXElementReader.attribute(kAXRoleAttribute, from: window),
                subrole: AXElementReader.attribute(kAXSubroleAttribute, from: window),
                title: AXElementReader.attribute(kAXTitleAttribute, from: window),
                bundleIdentifier: NSRunningApplication(processIdentifier: processID)?.bundleIdentifier,
                executableName: NSRunningApplication(processIdentifier: processID)?.executableURL?.lastPathComponent,
                frame: WindowFrameResolver.frame(of: window)?.frame,
                isMinimized: false,
                isFullScreen: isFullScreen == true
            )
            if let reason = SnapWindowEligibility.rejection(
                for: candidate, userExclusions: configuration.exclusionSet, honorsRestrictedList: configuration.honorsRestrictedApps
            ) {
                DiagnosticLogService.record(category: "windowManagement", action: "dragRejected", fields: ["reasonCode": reason])
                return
            }

            self.stateLock.lock()
            guard self.generation == token, self.dragState.downPoint != nil, self.dragState.window == nil else {
                self.stateLock.unlock()
                return
            }
            self.dragState.window = DraggedWindow(element: window, processID: processID)
            self.dragState.initialFrame = candidate.frame
            self.stateLock.unlock()
            DiagnosticLogService.record(category: "windowManagement", action: "dragResolved", fields: [
                "durationMS": String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - requestedAt) * 1000)
            ])
        }
    }

    /// Decides whether the window is being *moved*.
    ///
    /// A window that changes size is being resized, and a window whose frame has not moved at all
    /// means the gesture never grabbed it. Only an unchanged size plus a moved origin counts.
    private func sampleFrame(for window: DraggedWindow) {
        let token = currentGeneration()
        AXCommandQueue.shared.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            defer {
                self.stateLock.lock()
                if self.generation == token { self.dragState.frameSamplePending = false }
                self.stateLock.unlock()
            }
            guard let frame = WindowFrameResolver.frameFromAttributes(of: window.element) else { return }

            self.stateLock.lock()
            guard self.generation == token, self.dragState.downPoint != nil, let initial = self.dragState.initialFrame else {
                self.stateLock.unlock()
                return
            }
            let sizeChanged = abs(frame.width - initial.width) > self.movementTolerance
                || abs(frame.height - initial.height) > self.movementTolerance
            let originMoved = abs(frame.minX - initial.minX) > self.movementTolerance
                || abs(frame.minY - initial.minY) > self.movementTolerance

            let wasMoving = self.dragState.isMoving
            if sizeChanged {
                self.dragState.isResizing = true
                self.dragState.isMoving = false
            } else if originMoved {
                self.dragState.isMoving = true
            }
            self.dragState.lastFrame = frame
            let movementChanged = self.dragState.isMoving != wasMoving
            let state = WindowDragState(
                isMoving: self.dragState.isMoving,
                zone: self.dragState.lastZone,
                pointer: self.dragState.lastPoint ?? self.dragState.downPoint ?? .zero,
                windowFrame: frame,
                draggedWindow: self.dragState.window
            )
            self.stateLock.unlock()

            // Only the transition is published. Everything after it is driven by the pointer, which
            // is far cheaper and is what the zone actually depends on.
            guard movementChanged else { return }
            self.publish(state, token: token)
        }
    }

    private func updateZone(pointer: CGPoint, window: DraggedWindow?) {
        guard let screen = ScreenGeometryProvider.screen(containing: pointer) else { return }
        let configuration = configurationBox.current()
        stateLock.lock()
        let previousZone = dragState.lastZone
        stateLock.unlock()
        let result = SnapZonePolicy.result(
            pointer: pointer,
            screen: screen,
            configuration: configuration.effectiveZones,
            previous: previousZone
        )

        stateLock.lock()
        let changed = result != dragState.lastZone
        dragState.lastZone = result
        let isMoving = dragState.isMoving
        let frame = dragState.lastFrame
        // Hover feedback needs a steady stream of pointer updates, but only while something is
        // actually being hovered — and only when the pointer really moved. Without this gate the
        // island republished 60 times a second for a pointer that had not budged.
        let moved = dragState.lastPublishedPoint.map {
            hypot(pointer.x - $0.x, pointer.y - $0.y) >= 3
        } ?? true
        if changed || moved {
            dragState.lastPublishedPoint = pointer
        } else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        guard isMoving else { return }
        if changed {
            DiagnosticLogService.record(category: "windowManagement", action: "dragZoneChanged", fields: [
                "zone": result.zone.rawValue,
                "target": result.target?.diagnosticName ?? (result.isIslandActive ? "island" : "none"),
                "xRatio": String(format: "%.3f", (pointer.x - screen.frame.minX) / max(screen.frame.width, 1)),
                "yRatio": String(format: "%.3f", (pointer.y - screen.visibleFrame.minY) / max(screen.visibleFrame.height, 1))
            ])
        }
        publish(
            WindowDragState(
                isMoving: true,
                zone: result,
                pointer: pointer,
                windowFrame: frame,
                draggedWindow: window
            )
        )
    }

    private func currentGeneration() -> UInt64 {
        stateLock.lock(); defer { stateLock.unlock() }
        return generation
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        currentGeneration() == token
    }

    private func publish(_ state: WindowDragState, token: UInt64? = nil) {
        let token = token ?? currentGeneration()
        Task { @MainActor [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.onUpdate?(state)
        }
    }

    private static func windowFromServer(at point: CGPoint) -> AXUIElement? {
        guard let entry = WindowServerInventory.onScreenWindows().first(where: {
            $0.layer == 0 && $0.bounds.contains(point) && $0.bounds.width > 80 && $0.bounds.height > 60
        }) else { return nil }
        let application = AXUIElementCreateApplication(entry.processID)
        AXUIElementSetMessagingTimeout(application, 0.08)
        var windows = AXElementReader.elements(kAXWindowsAttribute, from: application)
        if windows.isEmpty {
            WindowFrameResolver.enableEnhancedUserInterface(for: entry.processID)
            windows = AXElementReader.elements(kAXWindowsAttribute, from: application)
        }
        return windows.first { window in
            AXUIElementSetMessagingTimeout(window, 0.06)
            if WindowFrameResolver.windowNumber(of: window) == entry.windowID { return true }
            guard let frame = WindowFrameResolver.frameFromAttributes(of: window) else { return false }
            return WindowSnapGeometry.framesApproximatelyEqual(frame, entry.bounds, tolerance: 3)
        }
    }

    private static func windowElement(from element: AXUIElement) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(element, 0.06)
        if let window: AXUIElement = AXElementReader.attribute(kAXWindowAttribute, from: element) {
            return window
        }
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else { return nil }
            let role: String? = AXElementReader.attribute(kAXRoleAttribute, from: candidate)
            if role == kAXWindowRole as String { return candidate }
            current = AXElementReader.attribute(kAXParentAttribute, from: candidate)
        }
        return nil
    }
}
