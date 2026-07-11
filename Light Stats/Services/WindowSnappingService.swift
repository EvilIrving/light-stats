//
//  WindowSnappingService.swift
//  Light Stats
//
//  Shared Accessibility-backed window positioning used by keyboard shortcuts and
//  titlebar trackpad gestures.
//

import AppKit
import ApplicationServices
import OSLog

struct WindowSnapHotKey: Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var action: WindowSnapAction
}

enum WindowSnapAction: Sendable, Hashable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftThird
    case leftTwoThirds
    case centerThird
    case rightTwoThirds
    case rightThird
    case nextDisplay
    case previousDisplay
    case maximize
    case center
    case restore
    case minimize
}

final class WindowSnappingService {
    private struct WindowIdentity: Hashable {
        var processID: pid_t
        var windowNumber: Int
        var title: String
    }

    private let logger = AppLogger(subsystem: "com.lightstats", category: "WindowSnapping")
    private var savedFrames: [WindowIdentity: CGRect] = [:]

    func checkPermission(promptIfNeeded: Bool) -> Bool {
        AccessibilityPermission.isTrusted(prompt: promptIfNeeded)
    }

    func perform(_ action: WindowSnapAction) {
        recordRequest(action)
        guard checkPermission(promptIfNeeded: false) else { return recordResult(action, success: false, reason: "permission") }
        guard let window = focusedWindow() else { return recordResult(action, success: false, reason: "focusedWindow") }
        recordResult(action, success: perform(action, on: window))
    }

    func perform(_ action: WindowSnapAction, at axPoint: CGPoint) {
        recordRequest(action)
        guard checkPermission(promptIfNeeded: false) else { return recordResult(action, success: false, reason: "permission") }
        guard let window = titlebarWindow(at: axPoint) else { return recordResult(action, success: false, reason: "titlebarWindow") }
        recordResult(action, success: perform(action, on: window))
    }

    func canPerform(_ action: WindowSnapAction) -> Bool {
        guard checkPermission(promptIfNeeded: false), let window = focusedWindow() else { return false }
        return canPerform(action, on: window)
    }

    func previewFrame(for action: WindowSnapAction, at axPoint: CGPoint) -> CGRect? {
        guard checkPermission(promptIfNeeded: false), let window = titlebarWindow(at: axPoint) else { return nil }
        guard canPerform(action, on: window) else { return nil }
        return previewFrame(for: action, on: window)
    }

    private func perform(_ action: WindowSnapAction, on window: AXUIElement) -> Bool {
        guard canPerform(action, on: window) else { return false }
        switch action {
        case .restore:
            return restore(window)
        case .minimize:
            return minimize(window)
        case .nextDisplay:
            return moveToAdjacentDisplay(window, direction: 1)
        case .previousDisplay:
            return moveToAdjacentDisplay(window, direction: -1)
        default:
            return snap(window, action: action)
        }
    }

    private func recordRequest(_ action: WindowSnapAction) {
        DiagnosticLogService.record(
            category: "windowManagement",
            action: "requested",
            fields: ["snapAction": String(describing: action)]
        )
    }

    private func recordResult(_ action: WindowSnapAction, success: Bool, reason: String = "") {
        DiagnosticLogService.record(
            level: success ? .info : .error,
            category: "windowManagement",
            action: success ? "succeeded" : "failed",
            fields: ["snapAction": String(describing: action), "reason": reason]
        )
    }

    private func focusedWindow() -> AXUIElement? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)

        if let focused: AXUIElement = copyAttribute(kAXFocusedWindowAttribute, from: appElement) {
            return focused
        }
        if let main: AXUIElement = copyAttribute(kAXMainWindowAttribute, from: appElement) {
            return main
        }
        return nil
    }

    private func titlebarWindow(at axPoint: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var rawElement: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(axPoint.x), Float(axPoint.y), &rawElement)
        guard error == .success, let element = rawElement else { return nil }

        if let window = titlebarWindowFromAccessibilityTree(element) {
            return window
        }
        return titlebarWindowFromGeometry(element, at: axPoint)
    }

    private func titlebarWindowFromAccessibilityTree(_ element: AXUIElement) -> AXUIElement? {
        let titleElementName = "AXTitleUIElement"
        var current: AXUIElement? = element
        var nearestWindow: AXUIElement?

        for _ in 0..<8 {
            guard let candidate = current else { break }
            let role: String? = copyAttribute(kAXRoleAttribute, from: candidate)
            if role == kAXWindowRole as String {
                nearestWindow = candidate
            }
            if role == "AXTitleBar" {
                return nearestWindow ?? copyAttribute(kAXWindowAttribute, from: candidate)
            }
            if let window: AXUIElement = copyAttribute(kAXWindowAttribute, from: candidate),
               let titleElement: AXUIElement = copyAttribute(titleElementName, from: window),
               CFEqual(candidate, titleElement) {
                return window
            }
            current = copyAttribute(kAXParentAttribute, from: candidate)
        }
        return nil
    }

    private func titlebarWindowFromGeometry(_ element: AXUIElement, at axPoint: CGPoint) -> AXUIElement? {
        guard let window = nearestWindow(from: element), let frame = frame(of: window) else { return nil }
        let titlebarHeight: CGFloat = 44
        let tolerance: CGFloat = 2
        let inHorizontalRange = axPoint.x >= frame.minX && axPoint.x <= frame.maxX
        let inTitleBand = axPoint.y >= frame.minY - tolerance && axPoint.y <= frame.minY + titlebarHeight
        return inHorizontalRange && inTitleBand ? window : nil
    }

    private func nearestWindow(from element: AXUIElement) -> AXUIElement? {
        if let window: AXUIElement = copyAttribute(kAXWindowAttribute, from: element) {
            return window
        }

        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else { break }
            let role: String? = copyAttribute(kAXRoleAttribute, from: candidate)
            if role == kAXWindowRole as String {
                return candidate
            }
            current = copyAttribute(kAXParentAttribute, from: candidate)
        }
        return nil
    }

    private func canPerform(_ action: WindowSnapAction, on window: AXUIElement) -> Bool {
        switch action {
        case .restore:
            return canRestore(window)
        case .minimize:
            return isMinimized(window) != true
        case .nextDisplay, .previousDisplay:
            return canMoveToAdjacentDisplay(window)
        default:
            return canSnap(window, action: action)
        }
    }

    private func canSnap(_ window: AXUIElement, action: WindowSnapAction) -> Bool {
        guard let currentFrame = frame(of: window), let targetFrame = snapTargetFrame(for: action, window: window) else {
            return false
        }
        return !framesApproximatelyEqual(currentFrame, targetFrame)
    }

    private func canMoveToAdjacentDisplay(_ window: AXUIElement) -> Bool {
        guard let currentFrame = frame(of: window), screen(containingAXFrame: currentFrame) != nil else { return false }
        return NSScreen.screens.count > 1
    }

    private func canRestore(_ window: AXUIElement) -> Bool {
        guard let identity = identity(for: window) else { return false }
        return savedFrames[identity] != nil
    }

    private func isMinimized(_ window: AXUIElement) -> Bool? {
        copyAttribute(kAXMinimizedAttribute, from: window)
    }

    private func snap(_ window: AXUIElement, action: WindowSnapAction) -> Bool {
        guard let currentFrame = frame(of: window), let targetFrame = snapTargetFrame(for: action, window: window) else { return false }

        saveFrameIfNeeded(currentFrame, for: window)
        guard setFrame(targetFrame, for: window) else { return false }
        performHapticFeedback()
        return true
    }

    private func previewFrame(for action: WindowSnapAction, on window: AXUIElement) -> CGRect? {
        guard let targetFrame = snapTargetFrame(for: action, window: window) else { return nil }
        return cocoaRect(fromAXRect: targetFrame)
    }

    private func snapTargetFrame(for action: WindowSnapAction, window: AXUIElement) -> CGRect? {
        guard let currentFrame = frame(of: window) else { return nil }
        if action == .center {
            return centeredFrame(for: window, currentFrame: currentFrame)
        }
        return targetFrame(for: action, currentFrame: currentFrame)
    }

    private func targetFrame(for action: WindowSnapAction, currentFrame: CGRect) -> CGRect? {
        guard let screen = screen(containingAXFrame: currentFrame) else { return nil }
        let visibleFrame = axRect(fromCocoaRect: screen.visibleFrame)
        if action == .minimize {
            return minimizePreviewFrame(in: visibleFrame)
        }
        return targetFrame(for: action, visibleFrame: visibleFrame, currentSize: currentFrame.size)
    }

    private func targetFrame(for action: WindowSnapAction, visibleFrame: CGRect, currentSize: CGSize) -> CGRect {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2
        let thirdWidth = visibleFrame.width / 3

        switch action {
        case .leftHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .rightHalf:
            return CGRect(x: visibleFrame.minX + halfWidth, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .topHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY + halfHeight, width: visibleFrame.width, height: halfHeight)
        case .topLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: visibleFrame.minX + halfWidth, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY + halfHeight, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: visibleFrame.minX + halfWidth, y: visibleFrame.minY + halfHeight, width: halfWidth, height: halfHeight)
        case .leftThird:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: thirdWidth, height: visibleFrame.height)
        case .leftTwoThirds:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: thirdWidth * 2, height: visibleFrame.height)
        case .centerThird:
            return CGRect(x: visibleFrame.minX + thirdWidth, y: visibleFrame.minY, width: thirdWidth, height: visibleFrame.height)
        case .rightTwoThirds:
            return CGRect(x: visibleFrame.minX + thirdWidth, y: visibleFrame.minY, width: thirdWidth * 2, height: visibleFrame.height)
        case .rightThird:
            return CGRect(x: visibleFrame.maxX - thirdWidth, y: visibleFrame.minY, width: thirdWidth, height: visibleFrame.height)
        case .maximize:
            return visibleFrame
        case .center:
            return centeredFrame(size: currentSize, in: visibleFrame)
        case .nextDisplay, .previousDisplay, .restore, .minimize:
            return visibleFrame
        }
    }

    private func minimizePreviewFrame(in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - 80,
            y: visibleFrame.maxY - 56,
            width: 160,
            height: 36
        )
    }

    private func centeredFrame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func centeredFrame(for window: AXUIElement, currentFrame: CGRect) -> CGRect? {
        guard let screen = screen(containingAXFrame: currentFrame) else { return nil }
        let visibleFrame = axRect(fromCocoaRect: screen.visibleFrame)
        let size = savedFrame(for: window)?.size ?? currentFrame.size
        return centeredFrame(size: size, in: visibleFrame)
    }

    private func moveToAdjacentDisplay(_ window: AXUIElement, direction: Int) -> Bool {
        guard let currentFrame = frame(of: window), let currentScreen = screen(containingAXFrame: currentFrame) else { return false }
        let sortedScreens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard let currentIndex = sortedScreens.firstIndex(of: currentScreen), sortedScreens.count > 1 else { return false }

        let targetIndex = (currentIndex + direction + sortedScreens.count) % sortedScreens.count
        let sourceVisible = axRect(fromCocoaRect: currentScreen.visibleFrame)
        let targetVisible = axRect(fromCocoaRect: sortedScreens[targetIndex].visibleFrame)
        let relativeX = (currentFrame.minX - sourceVisible.minX) / max(sourceVisible.width, 1)
        let relativeY = (currentFrame.minY - sourceVisible.minY) / max(sourceVisible.height, 1)
        let widthRatio = currentFrame.width / max(sourceVisible.width, 1)
        let heightRatio = currentFrame.height / max(sourceVisible.height, 1)
        let targetFrame = CGRect(
            x: targetVisible.minX + targetVisible.width * relativeX,
            y: targetVisible.minY + targetVisible.height * relativeY,
            width: targetVisible.width * widthRatio,
            height: targetVisible.height * heightRatio
        ).intersection(targetVisible)

        saveFrameIfNeeded(currentFrame, for: window)
        guard setFrame(targetFrame, for: window) else { return false }
        performHapticFeedback()
        return true
    }

    private func minimize(_ window: AXUIElement) -> Bool {
        let minimized = kCFBooleanTrue as CFTypeRef
        guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized) == .success else { return false }
        performHapticFeedback()
        return true
    }

    private func restore(_ window: AXUIElement) -> Bool {
        guard let identity = identity(for: window), let savedFrame = savedFrames[identity] else { return false }
        guard setFrame(savedFrame, for: window) else { return false }
        savedFrames.removeValue(forKey: identity)
        performHapticFeedback()
        return true
    }

    private func savedFrame(for window: AXUIElement) -> CGRect? {
        guard let identity = identity(for: window) else { return nil }
        return savedFrames[identity]
    }

    private func saveFrameIfNeeded(_ frame: CGRect, for window: AXUIElement) {
        guard let identity = identity(for: window), savedFrames[identity] == nil else { return }
        savedFrames[identity] = frame
    }

    private func identity(for window: AXUIElement) -> WindowIdentity? {
        var processID: pid_t = 0
        guard AXUIElementGetPid(window, &processID) == .success else { return nil }
        let number: Int = copyAttribute("AXWindowNumber", from: window) ?? 0
        let title: String = copyAttribute(kAXTitleAttribute, from: window) ?? ""
        return WindowIdentity(processID: processID, windowNumber: number, title: title)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position: CGPoint = valueAttribute(kAXPositionAttribute, from: window),
              let size: CGSize = valueAttribute(kAXSizeAttribute, from: window) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) -> Bool {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        if positionResult != .success || sizeResult != .success {
            logger.debug("Failed to set window frame: position=\(positionResult.rawValue), size=\(sizeResult.rawValue)")
            return false
        }
        return true
    }

    private func screen(containingAXFrame frame: CGRect) -> NSScreen? {
        let cocoaFrame = cocoaRect(fromAXRect: frame)
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    private func axRect(fromCocoaRect rect: CGRect) -> CGRect {
        let maxY = desktopMaxY()
        return CGRect(x: rect.minX, y: maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func cocoaRect(fromAXRect rect: CGRect) -> CGRect {
        let maxY = desktopMaxY()
        return CGRect(x: rect.minX, y: maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 1
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func desktopMaxY() -> CGFloat {
        NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
    }

    private func copyAttribute<T>(_ attribute: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func valueAttribute<T>(_ attribute: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        var output: T?
        if T.self == CGPoint.self {
            var point = CGPoint.zero
            guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
            output = point as? T
        } else if T.self == CGSize.self {
            var size = CGSize.zero
            guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
            output = size as? T
        }
        return output
    }

    private func performHapticFeedback() {
        Task { @MainActor in
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
