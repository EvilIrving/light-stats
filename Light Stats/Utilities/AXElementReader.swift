//
//  AXElementReader.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import ApplicationServices
import CoreGraphics

/// Thin, stateless reads over an `AXUIElement`.
///
/// Every Accessibility consumer in the app used to carry its own copy of these, including the
/// `AXValue` unwrapping, which is the part that is easy to get subtly wrong.
enum AXElementReader {

    static func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func elements(_ name: String, from element: AXUIElement) -> [AXUIElement] {
        attribute(name, from: element) ?? []
    }

    static func point(_ name: String, from element: AXUIElement) -> CGPoint? {
        value(name, from: element, type: .cgPoint)
    }

    static func size(_ name: String, from element: AXUIElement) -> CGSize? {
        value(name, from: element, type: .cgSize)
    }

    /// Position and size combined, in Accessibility space.
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(kAXPositionAttribute, from: element),
              let size = size(kAXSizeAttribute, from: element) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    static func processIdentifier(of element: AXUIElement) -> pid_t? {
        var processID: pid_t = 0
        guard AXUIElementGetPid(element, &processID) == .success else { return nil }
        return processID
    }

    /// Whether the app will accept a write to this attribute. Non-resizable windows refuse
    /// `AXSize` while still accepting `AXPosition`, and the engine has to tell those apart.
    static func isSettable(_ name: String, of element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private static func value<T>(_ name: String, from element: AXUIElement, type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success,
              let raw,
              CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(raw, to: AXValue.self)
        if type == .cgPoint {
            var point = CGPoint.zero
            guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
            return point as? T
        }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size as? T
    }
}
