//
//  PrivateWindowServerAPI.swift
//  Light Stats
//
//  The WindowServer behaviours the public APIs do not expose, resolved with `dlsym` rather than
//  linked:
//
//  1. which windows live on the Spaces that are not showing (`CGSCopyManagedDisplaySpaces` →
//     `CGSCopyWindowsWithOptionsAndTags`). Accessibility is Space-scoped — measured on macOS 26, a
//     two-window TextEdit publishes only the window of the active Space — so without this a window
//     on another desktop is not merely unraised, it is absent from the switcher;
//  2. full-size pixels of a window the ScreenCaptureKit enumeration cannot offer
//     (`CGSHWCaptureWindowList`). A minimised window has no `SCWindow`, and a window on another
//     Space is not in `SCShareableContent` either, so both used to render as a title with no picture;
//  3. switching *to* a window: `_SLPSSetFrontProcessWithOptions` fronts the process at that window
//     (which for another Space also moves the user there), `SLPSPostEventRecordTo` carries the
//     synthetic mouse-down that makes it key, and `SLSSpaceSetFrontPSN` gives the Space the user
//     left its own front process back.
//
//  Everything is one type with one resolved-once symbol table, so the private surface is exactly one
//  file long and every call site speaks Swift. Each failure degrades rather than crashing: a missing
//  symbol answers "nothing there", and the public-API behaviour — the Space-scoped Accessibility
//  list, the title-only card, the `AXRaise` focus — is what remains.
//
//  `#if !APP_STORE`: an App Store build compiles the no-op bodies. These are not symbols review
//  accepts, and the features are worth keeping in the App Store build, degraded.
//

import AppKit
import CoreGraphics
import Foundation

/// Resolved-once access to the private WindowServer behaviour the preview surfaces need.
///
/// `@unchecked Sendable`: the symbol table is written once during `init` and never again, and every
/// call is a plain C function call with no shared state of its own.
nonisolated final class PrivateWindowServerAPI: @unchecked Sendable {

    static let shared = PrivateWindowServerAPI()

    /// A front-process switch in progress: the window it targets and that process' serial number.
    ///
    /// One value spans steps 2 and 3 of a switch so `GetProcessForPID` is answered once — the front
    /// call and the make-key post have to name the same process, and it is a round trip each time.
    struct FrontProcessSwitch {
        var windowID: CGWindowID
        fileprivate var serialNumber: ProcessSerialNumber
    }

    private let logger = AppLogger(category: "WindowServer")

    // MARK: - Interface

    /// Window ids that live on Spaces which are not currently showing.
    ///
    /// Empty when the symbols are unavailable, which reads as "nothing is on another Space" and
    /// leaves the public-API rule in charge.
    func windowIDsOnInactiveSpaces() -> Set<CGWindowID> {
        #if APP_STORE
        return []
        #else
        guard let connection, let copyManagedDisplaySpaces, let copyWindows else { return [] }
        let inactive = inactiveSpaceIDs(copyManagedDisplaySpaces, connection)
        guard !inactive.isEmpty else { return [] }
        var setTags = 0
        var clearTags = 0
        guard let raw = copyWindows(connection, 0, inactive as CFArray, Self.allWindowOptions, &setTags, &clearTags) else {
            logger.debug("SLSCopyWindowsWithOptionsAndTags returned no windows")
            return []
        }
        guard let windowIDs = raw.takeRetainedValue() as? [CGWindowID] else { return [] }
        return Set(windowIDs)
        #endif
    }

    /// Whether `windowID` lives on a Space that is not showing.
    ///
    /// Has to be asked **before** the switch: fronting the window moves the user to it, and
    /// afterwards the target is on the active Space, so the question answers itself.
    func isOnInactiveSpace(windowID: CGWindowID) -> Bool {
        windowIDsOnInactiveSpaces().contains(windowID)
    }

    /// The Space showing on the main display, or `nil` when the symbol is unavailable.
    func activeSpaceID() -> UInt64? {
        #if APP_STORE
        return nil
        #else
        guard let connection, let activeSpace else { return nil }
        return activeSpace(connection)
        #endif
    }

    /// A full-size frame of `windowID`, minimised windows included.
    ///
    /// Not resized or cropped here: the caller owns the thumbnail geometry, so this returns what the
    /// WindowServer drew and nothing else. `nil` when the symbols are unavailable, the Screen
    /// Recording permission is missing, or the window is gone.
    func captureImage(windowID: CGWindowID) -> CGImage? {
        #if APP_STORE
        return nil
        #else
        guard let connection, let captureWindows else { return nil }
        var window = windowID
        guard let raw = captureWindows(connection, &window, 1, Self.captureOptions) else {
            logger.debug("CGSHWCaptureWindowList returned no image for window \(windowID)")
            return nil
        }
        guard let images = raw.takeRetainedValue() as? [CGImage] else { return nil }
        return images.first
        #endif
    }

    /// Fronts `processID` **at `windowID`**, which for a window on another Space also switches to
    /// that Space. Returns the handle `makeKeyWindow` needs, or `nil` when the symbols are
    /// unavailable or the WindowServer refused.
    ///
    /// `userGenerated` marks the switch as the user's, which is what keeps the WindowServer from
    /// suppressing it the way it suppresses an application's own activation requests.
    func frontProcess(processID: pid_t, windowID: CGWindowID) -> FrontProcessSwitch? {
        #if APP_STORE
        return nil
        #else
        guard let getProcessForPID, let setFrontProcess else { return nil }
        var serialNumber = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
        guard getProcessForPID(processID, &serialNumber) == 0 else { return nil }
        let status = setFrontProcess(&serialNumber, windowID, Self.userGeneratedFrontSwitch)
        if status != 0 {
            logger.debug("Front-process switch refused for pid \(processID): \(status)")
            return nil
        }
        return FrontProcessSwitch(windowID: windowID, serialNumber: serialNumber)
        #endif
    }

    /// Posts the synthetic left-mouse-down that makes a fronted window key.
    ///
    /// Fronting a process puts it at the front but leaves key focus where it was, and no public API
    /// moves key focus across processes. See `MakeKeyEvent` for why it is a down on its own, aimed
    /// far off the window.
    func makeKeyWindow(_ window: FrontProcessSwitch) {
        #if !APP_STORE
        guard let postEventRecord else { return }
        var serialNumber = window.serialNumber
        var bytes = MakeKeyEvent.record(windowID: window.windowID)
        let status = postEventRecord(&serialNumber, &bytes)
        if status != 0 {
            logger.debug("Make-key post refused for window \(window.windowID): \(status)")
        }
        #endif
    }

    /// Hands `spaceID` its own front process back.
    ///
    /// `_SLPSSetFrontProcessWithOptions` writes the *global* front process, so the Space the user
    /// left now remembers our application as its front and comes back showing our window instead of
    /// the one that was there. `SLSSpaceSetFrontPSN` writes one Space, which is why it repairs and
    /// does not switch.
    func restoreFrontProcess(spaceID: UInt64, processID: pid_t) {
        #if !APP_STORE
        guard let connection, let setSpaceFrontProcess, let getProcessForPID else { return }
        var serialNumber = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
        guard getProcessForPID(processID, &serialNumber) == 0 else { return }
        let status = setSpaceFrontProcess(connection, spaceID, serialNumber)
        if status != 0 {
            logger.debug("Front-process restore for Space \(spaceID) refused: \(status)")
        }
        #endif
    }

    // MARK: - Pure seams

    /// Byte layout of the `CGSEventRecord` the make-key post carries, ported from AltTab
    /// (`src/macos/api-wrappers/SkyLight.framework.swift`), which reverse-engineered it from
    /// CGSInternal's `CGSEvent.h`.
    enum MakeKeyEvent {
        /// Bytes allocated. The record itself is `recordLength` (0xf8) long; the rest is zeroed
        /// padding, because the WindowServer's encoder reads past a record whose buffer is exactly
        /// 0xf8 (paneru#123). yabai allocates the same 0x100.
        static let bufferSize = 0x100
        /// 0x04: the record's own declared length, which stays 0xf8 however wide the buffer is.
        static let lengthOffset = 0x04
        static let recordLength: UInt8 = 0xf8
        /// 0x08: the `CGSEventType`, matching the public `CGEventType` raw values.
        static let eventTypeOffset = 0x08
        static let leftMouseDown: UInt8 = 0x01
        /// 0x3a: purpose undocumented; yabai and Hammerspoon both set it to 0x10.
        static let unknownFlagOffset = 0x3a
        static let unknownFlagValue: UInt8 = 0x10
        /// 0x3c: the target `CGWindowID` — the event is delivered to this window, not to a point.
        static let windowIDOffset = 0x3c
        /// 0x20: the window-relative click point, a 16-byte `CGPoint`.
        static let windowLocationOffset = 0x20
        /// Far past the bottom-right corner of any conceivable window. A point inside the window
        /// lands on content that an app may activate (a top-left control is what (0, 0) hits when a
        /// value is sanitised), and a point a few points outside it sits in the resize grab region,
        /// which macOS 27 acts on.
        static let offContentPoint = CGPoint(x: 300_000, y: 300_000)

        /// The record, ready to hand to `SLPSPostEventRecordTo`.
        ///
        /// The down is posted alone, never paired with an up: the pair is what completes a click, and
        /// a completed click activates whatever control it lands on. Measured by AltTab on macOS 26.5
        /// — the down alone makes the right window key, and an up alone does nothing.
        static func record(windowID: CGWindowID) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: bufferSize)
            bytes[lengthOffset] = recordLength
            bytes[unknownFlagOffset] = unknownFlagValue
            var windowID = windowID
            memcpy(&bytes[windowIDOffset], &windowID, MemoryLayout<CGWindowID>.size)
            var point = offContentPoint
            memcpy(&bytes[windowLocationOffset], &point, MemoryLayout<CGPoint>.size)
            bytes[eventTypeOffset] = leftMouseDown
            return bytes
        }
    }

    /// The Spaces a display topology reports as *not* current, from `SLSCopyManagedDisplaySpaces`.
    ///
    /// The active Space is read per display — one active Space per display is the ordinary
    /// arrangement, and a display can show a different Space from its neighbour — with
    /// `SLSGetActiveSpace` covering a display dictionary that arrives without its `Current Space`:
    /// without it every Space would read as inactive, and the answer would become "every window on
    /// the system is on another Space". Pure, so the rule is testable without the symbols.
    static func inactiveSpaceIDs(displays: [[String: Any]], activeSpaceID: UInt64?) -> [UInt64] {
        let allSpaces = displays.flatMap { display in
            (display["Spaces"] as? [[String: Any]] ?? []).compactMap { $0["id64"] as? UInt64 }
        }
        var active = Set(displays.compactMap { ($0["Current Space"] as? [String: Any])?["id64"] as? UInt64 })
        if let activeSpaceID {
            active.insert(activeSpaceID)
        }
        return allSpaces.filter { !active.contains($0) }
    }

    #if !APP_STORE

    // MARK: - Symbols

    private typealias ConnectionID = Int32
    private typealias MainConnectionIDFn = @convention(c) () -> ConnectionID
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private typealias ActiveSpaceFn = @convention(c) (ConnectionID) -> UInt64
    private typealias CopyWindowsFn = @convention(c) (
        ConnectionID, Int32, CFArray, Int32, UnsafeMutablePointer<Int>, UnsafeMutablePointer<Int>
    ) -> Unmanaged<CFArray>?
    private typealias CaptureWindowsFn = @convention(c) (
        ConnectionID, UnsafeMutablePointer<CGWindowID>, UInt32, UInt32
    ) -> Unmanaged<CFArray>?
    private typealias GetProcessForPIDFn = @convention(c) (
        pid_t, UnsafeMutablePointer<ProcessSerialNumber>
    ) -> OSStatus
    private typealias SetFrontProcessFn = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32
    ) -> Int32
    private typealias PostEventRecordFn = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>
    ) -> Int32
    private typealias SetSpaceFrontProcessFn = @convention(c) (
        ConnectionID, UInt64, ProcessSerialNumber
    ) -> Int32

    /// Every window the Spaces hold, hidden and minimised ones included — "what is *in* this Space",
    /// as opposed to "what is currently drawn in it".
    private static let allWindowOptions = Int32(1 << 0 | 1 << 1 | 1 << 2)
    /// `ignoreGlobalClipShape | bestResolution | fullSize` — the combination that keeps a capture
    /// full-size under Stage Manager instead of clipped to its scaled tile.
    private static let captureOptions = UInt32(1 << 11 | 1 << 8 | 1 << 19)
    private static let userGeneratedFrontSwitch = UInt32(0x200)

    private let connection: ConnectionID?
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn?
    private let activeSpace: ActiveSpaceFn?
    private let copyWindows: CopyWindowsFn?
    private let captureWindows: CaptureWindowsFn?
    private let getProcessForPID: GetProcessForPIDFn?
    private let setFrontProcess: SetFrontProcessFn?
    private let postEventRecord: PostEventRecordFn?
    private let setSpaceFrontProcess: SetSpaceFrontProcessFn?

    private init() {
        // `dlopen(nil)` is the global symbol table — AppKit already pulls SkyLight in — and it is a
        // pseudo-handle that must never be closed. `GetProcessForPID` is not in it (measured), so it
        // is looked up in ApplicationServices, where the Process Manager still exports it.
        let global = dlopen(nil, RTLD_LAZY)
        let applicationServices = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            RTLD_LAZY
        )

        func resolve<Symbol>(_ name: String, in handle: UnsafeMutableRawPointer?, as type: Symbol.Type) -> Symbol? {
            guard let handle, let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: Symbol.self)
        }

        let mainConnectionID = resolve("CGSMainConnectionID", in: global, as: MainConnectionIDFn.self)
        copyManagedDisplaySpaces = resolve(
            "SLSCopyManagedDisplaySpaces", in: global, as: CopyManagedDisplaySpacesFn.self
        )
        activeSpace = resolve("SLSGetActiveSpace", in: global, as: ActiveSpaceFn.self)
        copyWindows = resolve("SLSCopyWindowsWithOptionsAndTags", in: global, as: CopyWindowsFn.self)
        captureWindows = resolve("CGSHWCaptureWindowList", in: global, as: CaptureWindowsFn.self)
        getProcessForPID = resolve("GetProcessForPID", in: applicationServices, as: GetProcessForPIDFn.self)
        setFrontProcess = resolve("_SLPSSetFrontProcessWithOptions", in: global, as: SetFrontProcessFn.self)
        postEventRecord = resolve("SLPSPostEventRecordTo", in: global, as: PostEventRecordFn.self)
        setSpaceFrontProcess = resolve("SLSSpaceSetFrontPSN", in: global, as: SetSpaceFrontProcessFn.self)
        connection = mainConnectionID?()

        let missing = [
            mainConnectionID == nil ? "CGSMainConnectionID" : nil,
            copyManagedDisplaySpaces == nil ? "SLSCopyManagedDisplaySpaces" : nil,
            activeSpace == nil ? "SLSGetActiveSpace" : nil,
            copyWindows == nil ? "SLSCopyWindowsWithOptionsAndTags" : nil,
            captureWindows == nil ? "CGSHWCaptureWindowList" : nil,
            getProcessForPID == nil ? "GetProcessForPID" : nil,
            setFrontProcess == nil ? "_SLPSSetFrontProcessWithOptions" : nil,
            postEventRecord == nil ? "SLPSPostEventRecordTo" : nil,
            setSpaceFrontProcess == nil ? "SLSSpaceSetFrontPSN" : nil
        ].compactMap { $0 }
        if missing.isEmpty {
            logger.info("Private WindowServer API resolved")
        } else {
            logger.error("Private WindowServer API incomplete; missing \(missing.joined(separator: ", "))")
        }
    }

    private func inactiveSpaceIDs(_ copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn, _ connection: ConnectionID) -> [UInt64] {
        guard let raw = copyManagedDisplaySpaces(connection) else {
            logger.debug("SLSCopyManagedDisplaySpaces returned no displays")
            return []
        }
        guard let displays = raw.takeRetainedValue() as? [[String: Any]] else { return [] }
        return Self.inactiveSpaceIDs(displays: displays, activeSpaceID: activeSpace.map { $0(connection) })
    }

    #else

    private init() {
        logger.info("App Store build: private WindowServer API compiled out")
    }

    #endif
}
