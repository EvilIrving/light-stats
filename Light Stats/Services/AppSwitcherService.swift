//
//  AppSwitcherService.swift
//  Light Stats
//

import AppKit
import CoreGraphics
import Foundation
import OSLog

/// The keys the switcher consumes.
///
/// A value type rather than raw key codes at each call site, so the mapping from a `CGEvent` to an
/// intent is one small function that can be read at a glance.
nonisolated enum AppSwitcherKey: Equatable {
    case begin(backwards: Bool)
    case next
    case previous
    case nextWindow
    case previousWindow
    case cancel
    /// Anything else: the switcher steps aside and the event continues to the application.
    case passthrough
}

protocol AppSwitcherControlling: AnyObject {
    var isRunning: Bool { get }
    /// The session moved; the controller draws it.
    var onSessionChanged: ((AppSwitcherSession) -> Void)? { get set }
    /// The user released ⌘ (commit) or pressed Escape (cancel).
    var onSessionEnded: ((_ committed: WindowPreviewItem?) -> Void)? { get set }
    func start() -> Bool
    func stop()
    func setSuspended(_ suspended: Bool)
    /// Supplies the applications and windows to switch between, on demand.
    var sessionProvider: (() -> AppSwitcherSession)? { get set }
}

/// Replaces ⌘Tab with a window-level switcher.
///
/// **This is the one service in the app that takes a system gesture away from macOS**, and the whole
/// design is shaped by that:
///
/// - the tap is **active** (`.defaultTap`), because the system switcher has to be suppressed — a
///   listen-only tap would show our panel *and* the system's;
/// - nothing is ever swallowed unless a session actually started. If the provider returns nothing,
///   or the panel cannot be shown, the event is passed through and macOS' own switcher works
///   normally. A switcher that eats ⌘Tab and then shows nothing is worse than not having one;
/// - any key that is not part of the gesture cancels the session and is passed through, so ⌘Q while
///   a session is open still quits the frontmost application instead of being silently dropped;
/// - the tap is torn down the moment the feature is switched off, and `stop()` cancels any session.
nonisolated final class AppSwitcherService: AppSwitcherControlling, @unchecked Sendable {

    private let logger = AppLogger(category: "AppSwitcher")
    private let stateLock = NSLock()

    private var running = false
    private var suspended = false
    private var session = AppSwitcherSession(groups: [])
    private var deliveryRevision: UInt64 = 0

    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onSessionChanged: ((AppSwitcherSession) -> Void)?
    var onSessionEnded: ((WindowPreviewItem?) -> Void)?
    var sessionProvider: (() -> AppSwitcherSession)?

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    var isSessionActive: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return session.isShowing
    }

    // MARK: - Lifecycle

    func start() -> Bool {
        guard !isRunning else { return true }
        guard AccessibilityPermission.isTrusted(prompt: false) else {
            logger.debug("App switcher needs Accessibility for an active event tap")
            return false
        }

        stateLock.lock()
        running = true
        stateLock.unlock()

        let thread = Thread { [weak self] in self?.runTapLoop() }
        thread.name = "com.lightstats.app-switcher"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        return true
    }

    func stop() {
        stateLock.lock()
        guard running else { stateLock.unlock(); return }
        running = false
        let hadSession = session.isShowing
        session.cancel()
        let loop = tapRunLoop
        stateLock.unlock()

        if hadSession {
            notifySessionEnded(nil)
        }
        if let loop {
            CFRunLoopStop(loop)
        }
        tapThread = nil
    }

    func setSuspended(_ suspended: Bool) {
        stateLock.lock()
        self.suspended = suspended
        if suspended {
            session.cancel()
        }
        stateLock.unlock()
        if suspended {
            notifySessionEnded(nil)
        }
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
        logger.info("App switcher started")

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
        logger.info("App switcher stopped")
    }

    private func makeTap() -> (CFMachPort, CFRunLoopSource)? {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<AppSwitcherService>.fromOpaque(refcon).takeUnretainedValue()
            let disposition = service.handle(type: type, event: event)
            // The callback's contract: return the event to pass it on, `nil` to swallow it.
            return disposition == .swallow ? nil : Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            // Active, not listen-only: suppressing the system switcher is the whole point.
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Failed to create app switcher event tap")
            return nil
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("Failed to create run loop source for app switcher tap")
            return nil
        }
        return (tap, source)
    }

    private enum Disposition { case pass, swallow }

    private func handle(type: CGEventType, event: CGEvent) -> Disposition {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelIfActive()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return .pass
        }

        stateLock.lock()
        let isRunning = running
        let isSuspended = suspended
        let isShowing = session.isShowing
        stateLock.unlock()
        guard isRunning, !isSuspended else { return .pass }

        switch type {
        case .keyDown:
            return handleKeyDown(event: event, isShowing: isShowing)
        case .flagsChanged:
            // Command released: the gesture is over and the selection is committed.
            guard isShowing, !event.flags.contains(.maskCommand) else { return .pass }
            commit()
            // Not swallowed: the flagsChanged event carries no action, and eating it would confuse
            // anything else watching modifier state.
            return .pass
        default:
            return .pass
        }
    }

    private func handleKeyDown(event: CGEvent, isShowing: Bool) -> Disposition {
        let key = Self.intent(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags,
            isShowing: isShowing
        )

        // Anything that is not part of the gesture ends the session and continues to the
        // application — so ⌘Q while the switcher is open still quits instead of being dropped.
        if case .passthrough = key {
            if isShowing { cancel() }
            return .pass
        }

        // Tab starts the session, and starting one is the only thing that may happen while none is
        // open. If there is nothing to switch to, the event goes back to the system switcher rather
        // than being swallowed into a panel that never appears.
        if case .begin(let backwards) = key {
            guard !isShowing, beginSession(backwards: backwards) else { return .pass }
            publishSession()
            return .swallow
        }

        guard isShowing else { return .pass }

        switch key {
        case .next:
            mutateSession { $0.advance(by: 1) }
        case .previous:
            mutateSession { $0.advance(by: -1) }
        case .nextWindow:
            mutateSession { $0.moveWindow(by: 1) }
        case .previousWindow:
            mutateSession { $0.moveWindow(by: -1) }
        case .cancel:
            // Escape while the switcher is open must not reach the application — with ⌘ held it
            // would otherwise be some other command.
            cancel()
            return .swallow
        case .begin, .passthrough:
            return .pass
        }
        publishSession()
        return .swallow
    }

    /// The keys this switcher understands, by Carbon virtual key code.
    enum KeyCode {
        static let tab: Int64 = 48
        static let escape: Int64 = 53
        static let leftArrow: Int64 = 123
        static let rightArrow: Int64 = 124
        static let downArrow: Int64 = 125
        static let upArrow: Int64 = 126
    }

    /// Maps a key event to an intent. Pure, so the whole key model is readable in one place.
    static func intent(keyCode: Int64, flags: CGEventFlags, isShowing: Bool) -> AppSwitcherKey {
        let hasCommand = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)

        switch keyCode {
        case KeyCode.tab:
            return tabIntent(hasCommand: hasCommand, hasShift: hasShift, isShowing: isShowing)
        case KeyCode.upArrow, KeyCode.leftArrow:
            return hasCommand && isShowing ? .previousWindow : .passthrough
        case KeyCode.downArrow, KeyCode.rightArrow:
            return hasCommand && isShowing ? .nextWindow : .passthrough
        case KeyCode.escape:
            return isShowing ? .cancel : .passthrough
        default:
            // ⌘` walks the current application's windows on macOS; the switcher already puts every
            // window one Tab away, so it is left to the system.
            return .passthrough
        }
    }

    /// Tab is the only key whose meaning depends on whether a session is already open: it starts one
    /// when there is none, and moves the selection when there is.
    private static func tabIntent(hasCommand: Bool, hasShift: Bool, isShowing: Bool) -> AppSwitcherKey {
        guard hasCommand else { return .passthrough }
        guard isShowing else { return .begin(backwards: hasShift) }
        return hasShift ? .previous : .next
    }

    // MARK: - Session

    private func beginSession(backwards: Bool) -> Bool {
        guard let provider = sessionProvider else { return false }
        var candidate = provider()
        guard candidate.selectedWindow != nil else { return false }
        candidate.selectInitialGroup(backwards: backwards)

        stateLock.lock()
        guard running, !suspended else { stateLock.unlock(); return false }
        session = candidate
        stateLock.unlock()
        return true
    }

    private func mutateSession(_ update: (inout AppSwitcherSession) -> Void) {
        stateLock.lock(); defer { stateLock.unlock() }
        guard running, !suspended, session.isShowing else { return }
        update(&session)
    }

    private func isCurrentDelivery(_ revision: UInt64) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return deliveryRevision == revision
    }

    private func publishSession() {
        stateLock.lock()
        let current = session
        deliveryRevision &+= 1
        let revision = deliveryRevision
        stateLock.unlock()
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentDelivery(revision) else { return }
            self.onSessionChanged?(current)
        }
    }

    private func commit() {
        stateLock.lock()
        let window = session.commit()
        stateLock.unlock()
        notifySessionEnded(window)
    }

    private func cancel() {
        stateLock.lock()
        session.cancel()
        stateLock.unlock()
        notifySessionEnded(nil)
    }

    private func cancelIfActive() {
        stateLock.lock()
        let wasShowing = session.isShowing
        session.cancel()
        stateLock.unlock()
        if wasShowing {
            notifySessionEnded(nil)
        }
    }

    private func notifySessionEnded(_ window: WindowPreviewItem?) {
        stateLock.lock()
        deliveryRevision &+= 1
        let revision = deliveryRevision
        stateLock.unlock()
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentDelivery(revision) else { return }
            self.onSessionEnded?(window)
        }
    }
}
