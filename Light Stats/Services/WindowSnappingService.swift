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

enum WindowSnapAction: Sendable, Equatable {
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

    private let logger = Logger(subsystem: "com.lightstats", category: "WindowSnapping")
    private var savedFrames: [WindowIdentity: CGRect] = [:]

    func checkPermission(promptIfNeeded: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func perform(_ action: WindowSnapAction) {
        guard checkPermission(promptIfNeeded: false) else { return }
        guard let window = focusedWindow() else { return }
        perform(action, on: window)
    }

    func perform(_ action: WindowSnapAction, at axPoint: CGPoint) {
        guard checkPermission(promptIfNeeded: false) else { return }
        guard let window = titlebarWindow(at: axPoint) else { return }
        perform(action, on: window)
    }

    private func perform(_ action: WindowSnapAction, on window: AXUIElement) {
        switch action {
        case .restore:
            restore(window)
        case .minimize:
            minimize(window)
        case .nextDisplay:
            moveToAdjacentDisplay(window, direction: 1)
        case .previousDisplay:
            moveToAdjacentDisplay(window, direction: -1)
        default:
            snap(window, action: action)
        }
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

    private func snap(_ window: AXUIElement, action: WindowSnapAction) {
        guard let currentFrame = frame(of: window), let screen = screen(containingAXFrame: currentFrame) else { return }
        let visibleFrame = axRect(fromCocoaRect: screen.visibleFrame)
        let targetFrame = targetFrame(for: action, visibleFrame: visibleFrame, currentSize: currentFrame.size)

        saveFrameIfNeeded(currentFrame, for: window)
        guard setFrame(targetFrame, for: window) else { return }
        performHapticFeedback()
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

    private func moveToAdjacentDisplay(_ window: AXUIElement, direction: Int) {
        guard let currentFrame = frame(of: window), let currentScreen = screen(containingAXFrame: currentFrame) else { return }
        let sortedScreens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard let currentIndex = sortedScreens.firstIndex(of: currentScreen), sortedScreens.count > 1 else { return }

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
        guard setFrame(targetFrame, for: window) else { return }
        performHapticFeedback()
    }

    private func minimize(_ window: AXUIElement) {
        let minimized = kCFBooleanTrue as CFTypeRef
        guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized) == .success else { return }
        performHapticFeedback()
    }

    private func restore(_ window: AXUIElement) {
        guard let identity = identity(for: window), let savedFrame = savedFrames[identity] else { return }
        guard setFrame(savedFrame, for: window) else { return }
        savedFrames.removeValue(forKey: identity)
        performHapticFeedback()
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
