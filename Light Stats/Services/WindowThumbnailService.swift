//
//  WindowThumbnailService.swift
//  Light Stats
//

import AppKit
import CoreGraphics
import OSLog
import ScreenCaptureKit

/// Captures and caches window thumbnails.
///
/// ScreenCaptureKit is the only path to another window's pixels, and it is TCC-gated, so this
/// service is careful about two things:
///
/// 1. **It never captures unless it has to.** `SCShareableContent` is a full enumeration of every
///    window on the system and is far more expensive than a single capture, so it is refreshed on a
///    timer and reused.
/// 2. **It never blocks a caller.** Capture is async and the result is cached, so hovering across a
///    Dock with eight windows does not queue eight synchronous captures behind each other.
///
/// Capture is also the only thing here that needs Screen Recording. Everything else about the
/// preview — titles, ordering, the AX join — works without it, which is what lets the same surfaces
/// degrade to a title list instead of disappearing.
actor WindowThumbnailService {

    private struct CacheKey: Hashable {
        var windowID: CGWindowID
        var width: Int
    }

    private struct CacheEntry {
        var image: CGImage
        var capturedAt: TimeInterval
    }

    private let logger = AppLogger(category: "WindowThumbnails")

    /// Thumbnails of a live window age: a page scrolls, a video plays. Long enough that hovering
    /// back and forth is free, short enough that the picture is not obviously stale.
    private let cacheLifetime: TimeInterval = 4
    /// `SCShareableContent` enumeration validity. Cheaper than capturing, dearer than everything
    /// else, so it sits between the two.
    private let shareableLifetime: TimeInterval = 2
    /// Bounded so a long session cannot grow without limit; thumbnails are large.
    private let maximumCacheEntries = 48

    private var cache: [CacheKey: CacheEntry] = [:]
    private var shareableWindows: [CGWindowID: SCWindow] = [:]
    private var shareableRefreshedAt: TimeInterval = -.infinity
    /// Set when a capture fails with an authorization error, so a denied permission does not cause
    /// one failed enumeration per hover for the rest of the session.
    private var isCaptureDenied = false
    private var inFlight: [CacheKey: Task<CGImage?, Never>] = [:]
    private var generation: UInt64 = 0
    private var shareableTask: Task<ShareableSnapshot?, Never>?

    private struct ShareableSnapshot: @unchecked Sendable {
        var windows: [CGWindowID: SCWindow]
    }

    // MARK: - Public

    /// Whether the process can capture right now. Cheap, and deliberately not cached: the whole
    /// point is to notice the moment the user grants it.
    nonisolated static var isAuthorized: Bool {
        ScreenRecordingPermission.isGranted
    }

    func clearCache() {
        generation &+= 1
        for task in inFlight.values { task.cancel() }
        shareableTask?.cancel()
        shareableTask = nil
        cache.removeAll()
        shareableWindows.removeAll()
        shareableRefreshedAt = -.infinity
        inFlight.removeAll()
    }

    func purgeExpired() {
        let now = ProcessInfo.processInfo.systemUptime
        cache = cache.filter { now - $0.value.capturedAt < cacheLifetime }
        if now - shareableRefreshedAt >= shareableLifetime { shareableWindows.removeAll() }
    }

    func notePermissionDenied() {
        isCaptureDenied = true
    }

    func notePermissionGranted() {
        isCaptureDenied = false
        shareableRefreshedAt = -.infinity
    }

    /// A thumbnail of `windowID` at roughly `width` points.
    ///
    /// - Returns: `nil` when the window is gone, the permission is missing, or the capture failed —
    ///   all of which the caller renders as a title-only card.
    func thumbnail(for windowID: CGWindowID, width: CGFloat, title: String?) async -> CGImage? {
        guard !isCaptureDenied, ScreenRecordingPermission.isGranted else {
            return nil
        }

        let targetWidth = Self.pixelWidth(for: width)
        let key = CacheKey(windowID: windowID, width: targetWidth)
        let now = ProcessInfo.processInfo.systemUptime
        if let entry = cache.first(where: {
            $0.key.windowID == windowID && $0.key.width >= targetWidth && now - $0.value.capturedAt < cacheLifetime
        })?.value {
            return entry.image
        }
        // One capture per window at a time: the Dock preview and the app switcher can ask for the
        // same window in the same frame.
        if let task = inFlight.first(where: { $0.key.windowID == windowID && $0.key.width >= targetWidth })?.value {
            return await task.value
        }
        let token = generation
        let task = Task { [weak self] () -> CGImage? in
            guard let self, !Task.isCancelled else { return nil }
            if let window = await self.shareableWindow(for: windowID), !Task.isCancelled {
                return await self.capture(window: window, width: targetWidth)
            }
            guard !Task.isCancelled else { return nil }
            return await self.captureByWindowID(windowID, width: targetWidth)
        }
        inFlight[key] = task
        let image = await task.value
        guard generation == token else { return nil }
        inFlight[key] = nil
        guard let image, !Task.isCancelled else { return nil }
        cache[key] = CacheEntry(image: image, capturedAt: ProcessInfo.processInfo.systemUptime)
        trimCache()
        return image
    }

    func prewarm(_ items: [WindowPreviewItem], width: CGFloat) async {
        guard ScreenRecordingPermission.isGranted else { return }
        for item in items.prefix(6) {
            guard let windowID = item.windowID, !Task.isCancelled else { continue }
            _ = await thumbnail(for: windowID, width: width, title: nil)
        }
    }

    // MARK: - Enumeration

    private func shareableWindow(for windowID: CGWindowID) async -> SCWindow? {
        if let cached = shareableWindows[windowID], isShareableFresh {
            return cached
        }
        // A window that is missing from a *fresh* snapshot is one ScreenCaptureKit will not offer —
        // a minimised window, or one on another Space — so enumerating again would answer the same
        // thing twice. That matters now that such a window is the ordinary case rather than a race:
        // the enumeration is the most expensive call in this file and every card would pay it.
        await refreshShareableWindows()
        return shareableWindows[windowID]
    }

    private var isShareableFresh: Bool {
        ProcessInfo.processInfo.systemUptime - shareableRefreshedAt < shareableLifetime
    }

    private func refreshShareableWindows() async {
        let token = generation
        let task: Task<ShareableSnapshot?, Never>
        if let pending = shareableTask {
            task = pending
        } else {
            task = Task { [weak self] in await self?.readShareableSnapshot() }
            shareableTask = task
        }
        let snapshot = await task.value
        guard generation == token, !Task.isCancelled else { return }
        shareableTask = nil
        if let snapshot {
            shareableWindows = snapshot.windows
            shareableRefreshedAt = ProcessInfo.processInfo.systemUptime
        }
    }

    private func readShareableSnapshot() async -> ShareableSnapshot? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            guard !Task.isCancelled else { return nil }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            var windows: [CGWindowID: SCWindow] = [:]
            for window in content.windows where window.owningApplication?.processID != ownPID {
                windows[window.windowID] = window
            }
            return ShareableSnapshot(windows: windows)
        } catch {
            let nsError = error as NSError
            logger.debug("Shareable content unavailable: \(nsError.domain)/\(nsError.code)")
            DiagnosticLogService.record(level: .error, category: "windowManagement", action: "thumbnailUnavailable", fields: [
                "reasonCode": "shareableContentFailed", "domain": nsError.domain, "code": String(nsError.code)
            ])
            // A TCC denial surfaces here. Recording it stops the retry loop that would otherwise run
            // on every hover for the rest of the session.
            if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
                isCaptureDenied = true
            }
            return nil
        }
    }

    // MARK: - Capture

    private func capture(window: SCWindow, width: Int) async -> CGImage? {
        let started = ProcessInfo.processInfo.systemUptime
        let height = Self.pixelHeight(for: window.frame.size, width: width)
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.captureResolution = .best
        // The drop shadow is a third of a window's bounding box and is pure noise in a thumbnail.
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            DiagnosticLogService.record(category: "windowManagement", action: "thumbnailCaptured", fields: [
                "width": String(image.width), "height": String(image.height),
                "durationMS": String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - started) * 1000)
            ])
            return image
        } catch {
            let nsError = error as NSError
            logger.debug("Thumbnail capture failed for window \(window.windowID): \(nsError.code)")
            DiagnosticLogService.record(level: .error, category: "windowManagement", action: "thumbnailUnavailable", fields: [
                "reasonCode": "captureFailed", "domain": nsError.domain, "code": String(nsError.code)
            ])
            if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
                isCaptureDenied = true
            }
            return nil
        }
    }

    // MARK: - Fallback capture

    /// Pixels for a window ScreenCaptureKit has no `SCWindow` for: a minimised one, or one on a
    /// Space that is not showing.
    ///
    /// It is the same thumbnail — through the same cache, the same in-flight task, the same
    /// permission gate and the same trimmed pixel width — rather than a second pipeline. Only the
    /// capture call differs, because that is the only part `SCShareableContent` cannot serve.
    private func captureByWindowID(_ windowID: CGWindowID, width: Int) -> CGImage? {
        let started = ProcessInfo.processInfo.systemUptime
        guard let fullSize = PrivateWindowServerAPI.shared.captureImage(windowID: windowID) else {
            DiagnosticLogService.record(level: .error, category: "windowManagement", action: "thumbnailUnavailable", fields: [
                "reasonCode": "windowServerCaptureUnavailable", "windowID": String(windowID)
            ])
            return nil
        }
        // The WindowServer always answers full size — a 1280pt-wide window is 2560 pixels — so the
        // thumbnail is scaled down here, by the same aspect rule the ScreenCaptureKit path asks its
        // configuration for.
        let height = Self.pixelHeight(
            for: CGSize(width: fullSize.width, height: fullSize.height), width: width
        )
        guard let image = Self.resized(fullSize, to: CGSize(width: width, height: height)) else { return nil }
        DiagnosticLogService.record(category: "windowManagement", action: "thumbnailCaptured", fields: [
            "source": "windowServer", "width": String(image.width), "height": String(image.height),
            "durationMS": String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - started) * 1000)
        ])
        return image
    }

    /// Scales a full-size frame down to the thumbnail size, keeping its own aspect.
    static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Sizing

    /// Pixel width for a requested point width, clamped so a very wide Dock preview cannot ask for a
    /// 6K capture of every window.
    static func pixelWidth(for width: CGFloat) -> Int {
        Int(min(max(width, 120), 720))
    }

    /// Height that preserves the window's aspect ratio, so a tall window is not squashed into a
    /// letterbox.
    static func pixelHeight(for size: CGSize, width: Int) -> Int {
        guard size.width > 1, size.height > 1 else { return Int(Double(width) * 0.62) }
        let ratio = size.height / size.width
        return min(max(Int((Double(width) * ratio).rounded()), 80), 1_200)
    }

    private func trimCache() {
        guard cache.count > maximumCacheEntries else { return }
        let sorted = cache.sorted { $0.value.capturedAt < $1.value.capturedAt }
        for entry in sorted.prefix(cache.count - maximumCacheEntries) {
            cache[entry.key] = nil
        }
    }
}
