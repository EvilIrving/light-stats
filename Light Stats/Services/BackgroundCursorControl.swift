//
//  BackgroundCursorControl.swift
//  Light Stats
//
//  Grants this never-activating background app permission to control the system
//  cursor's visibility.
//
//  `CGDisplayHideCursor` only takes effect for the foreground application, so from a
//  menu-bar app it returns `.success` and does nothing at all — which is exactly the
//  "system arrow and overlay cursor at the same time" symptom. Setting the CoreGraphics
//  connection property `SetsCursorInBackground` on this process' own main WindowServer
//  connection lifts that restriction, and then the existing balanced
//  `CGDisplayHideCursor`/`CGDisplayShowCursor` pair actually applies.
//
//  The symbols are resolved with `dlsym` rather than linked, so a future OS that drops
//  them degrades to the old foreground-only behaviour instead of failing to launch.
//
//  Residual limitation, measured rather than guessed: while the pointer is over the Dock
//  the WindowServer keeps the Dock in cursor control, which can block the grant and let
//  the arrow reappear for as long as the pointer stays there.
//

import CoreGraphics
import Foundation

/// One-time installation of the background-cursor grant. The system call is the only
/// thing here that touches the machine, and it is injected so the once-only decision —
/// including what happens when the symbols are gone — is testable without it.
nonisolated struct BackgroundCursorControl {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias SetConnectionPropertyFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private typealias CursorIsVisibleFn = @convention(c) () -> boolean_t

    private static let logger = AppLogger(category: "PresentationPointer")
    /// `CGCursorIsVisible` is deprecated in the SDK but still answers; resolving it with
    /// `dlsym` keeps the deprecation warning out of the build. Nil on a system that
    /// dropped it.
    private static let cursorIsVisible: (() -> Bool)? = resolveCursorIsVisible()

    private let install: () -> Bool
    private var isConfigured = false
    private var lastResult = false

    init(install: @escaping () -> Bool = BackgroundCursorControl.installProperty) {
        self.install = install
    }

    /// Install the grant, at most once. A failure is remembered rather than retried: the
    /// caller keeps the foreground-only baseline for the rest of the process, and the
    /// presentation pointer stays a visible overlay instead of taking the cursor away.
    @discardableResult
    mutating func enableOnce() -> Bool {
        guard !isConfigured else { return lastResult }
        isConfigured = true
        lastResult = install()
        return lastResult
    }

    private static func installProperty() -> Bool {
        // `dlopen(nil)` is the global symbol table (AppKit already pulls SkyLight in) and
        // is a pseudo-handle that must not be closed.
        guard let handle = dlopen(nil, RTLD_LAZY),
              let connectionSymbol = dlsym(handle, "CGSMainConnectionID"),
              let propertySymbol = dlsym(handle, "CGSSetConnectionProperty") else {
            logger.error("Background cursor control unavailable; the system arrow stays over the pointer")
            return false
        }

        let mainConnectionID = unsafeBitCast(connectionSymbol, to: MainConnectionIDFn.self)
        let setConnectionProperty = unsafeBitCast(propertySymbol, to: SetConnectionPropertyFn.self)
        let connection = mainConnectionID()
        let status = setConnectionProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue!)

        guard status == 0 else {
            logger.error("SetsCursorInBackground failed with status \(status); the system arrow stays over the pointer")
            return false
        }
        logger.info("Background cursor control enabled")
        return true
    }

    /// Whether the window server is currently drawing the cursor. Nil when the symbol is
    /// unavailable — the caller re-asserts either way and only uses this to say why.
    static func isSystemCursorVisible() -> Bool? {
        cursorIsVisible?()
    }

    private static func resolveCursorIsVisible() -> (() -> Bool)? {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, "CGCursorIsVisible") else {
            return nil
        }
        let query = unsafeBitCast(symbol, to: CursorIsVisibleFn.self)
        return { query() != 0 }
    }
}
