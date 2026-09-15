//
//  WindowGestureTargeting.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import ApplicationServices
import CoreGraphics

/// Resolves what a swipe gesture at a screen point should act on.
///
/// This is the part of window management that cannot be made exact: a window's titlebar is not an
/// Accessibility concept (`AXTitlebar` and `AXTitleUIElement` are nil on AppKit and Electron windows
/// alike), and Electron draws its own titlebar inside the web content. So the zone decision here is
/// a heuristic — a measured titlebar band, plus a refusal to start on anything the app reacts to —
/// with `SnapGestureZone.pointer` as the escape hatch. See
/// `docs/window-titlebar-gesture-research.md`.
nonisolated struct WindowGestureTargeting {

    /// Either the window to act on, or why the point was refused.
    struct Target {
        var window: AXUIElement?
        var rejection: String?
    }

    /// Roles that mean "the app will do something with this event". Deliberately excludes
    /// `AXScrollArea` / `AXTextArea` / `AXGroup`: Electron windows report their whole web content —
    /// custom titlebar included — as one of those, so treating them as controls would refuse the
    /// gesture on every Electron window.
    private let controlRoles: Set<String> = [
        "AXButton", "AXTextField", "AXPopUpButton", "AXCheckBox", "AXRadioButton",
        "AXTabGroup", "AXScrollBar", "AXMenuButton", "AXSlider", "AXLink", "AXComboBox",
        "AXDisclosureTriangle", "AXSegmentedControl", "AXIncrementor"
    ]

    private let trafficLightSubroles: Set<String> = [
        "AXCloseButton", "AXMinimizeButton", "AXFullScreenButton", "AXZoomButton"
    ]

    func target(at axPoint: CGPoint, zone: SnapGestureZone) -> Target {
        guard let element = element(at: axPoint) else { return Target(window: nil, rejection: "noElement") }

        // A window that names its own titlebar is trusted over any geometry, though modern AppKit
        // and Electron windows never do.
        let namedTitlebar = titlebarWindow(fromAccessibilityTree: element)
        guard let window = nearestWindow(from: element) ?? namedTitlebar else {
            return Target(window: nil, rejection: "noWindow")
        }
        guard zone == .titlebar, namedTitlebar == nil else { return Target(window: window, rejection: nil) }

        guard let windowFrame = AXElementReader.frame(of: window) else {
            return Target(window: window, rejection: "noWindowFrame")
        }
        let trafficLights = trafficLights(of: window)
        guard WindowSnapGeometry.isInTitlebar(axPoint, windowFrame: windowFrame, trafficLights: trafficLights) else {
            return Target(window: window, rejection: "notTitlebar")
        }
        guard !isOnControl(at: axPoint, element: element, window: window, trafficLights: trafficLights) else {
            return Target(window: window, rejection: "control")
        }
        return Target(window: window, rejection: nil)
    }

    private func element(at axPoint: CGPoint) -> AXUIElement? {
        var raw: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(axPoint.x),
            Float(axPoint.y),
            &raw
        )
        guard error == .success else { return nil }
        return raw
    }

    /// Union of the window's traffic-light buttons.
    ///
    /// The system keeps them in the titlebar and exposes their coordinates on native and Electron
    /// windows alike, which makes their inset the only per-app titlebar measurement reachable from
    /// another process.
    private func trafficLights(of window: AXUIElement) -> CGRect? {
        var union: CGRect?
        for child in AXElementReader.elements(kAXChildrenAttribute, from: window) {
            let subrole: String = AXElementReader.attribute(kAXSubroleAttribute, from: child) ?? ""
            guard trafficLightSubroles.contains(subrole), let childFrame = AXElementReader.frame(of: child) else {
                continue
            }
            union = union.map { $0.union(childFrame) } ?? childFrame
        }
        return union
    }

    /// Whether a gesture would start on something the app itself reacts to.
    ///
    /// The event tap is listen-only, so a swipe over a control cannot be swallowed: without this
    /// check the app's own reaction (switch tab, move a slider) runs *and* the window snaps.
    private func isOnControl(
        at axPoint: CGPoint,
        element: AXUIElement,
        window: AXUIElement,
        trafficLights: CGRect?
    ) -> Bool {
        // Hit testing inside the traffic lights is inconsistent across apps (some report the
        // button, others only the row container), so the cluster rect is checked directly.
        if let trafficLights, trafficLights.insetBy(dx: -3, dy: -3).contains(axPoint) {
            return true
        }

        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else { break }
            if CFEqual(candidate, window) { break }
            let role: String = AXElementReader.attribute(kAXRoleAttribute, from: candidate) ?? ""
            if controlRoles.contains(role) { return true }
            current = AXElementReader.attribute(kAXParentAttribute, from: candidate)
        }
        return false
    }

    private func nearestWindow(from element: AXUIElement) -> AXUIElement? {
        if let window: AXUIElement = AXElementReader.attribute(kAXWindowAttribute, from: element) {
            return window
        }

        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else { break }
            let role: String? = AXElementReader.attribute(kAXRoleAttribute, from: candidate)
            if role == kAXWindowRole as String { return candidate }
            current = AXElementReader.attribute(kAXParentAttribute, from: candidate)
        }
        return nil
    }

    /// Walks up looking for a window that identifies a titlebar. Rarely fires, but it is the one
    /// signal better than geometry when an app does provide it.
    private func titlebarWindow(fromAccessibilityTree element: AXUIElement) -> AXUIElement? {
        let titleElementName = "AXTitleUIElement"
        var current: AXUIElement? = element
        var nearest: AXUIElement?

        for _ in 0..<8 {
            guard let candidate = current else { break }
            let role: String? = AXElementReader.attribute(kAXRoleAttribute, from: candidate)
            if role == kAXWindowRole as String {
                nearest = candidate
            }
            if role == "AXTitleBar" {
                return nearest ?? AXElementReader.attribute(kAXWindowAttribute, from: candidate)
            }
            if let window: AXUIElement = AXElementReader.attribute(kAXWindowAttribute, from: candidate),
               let titleElement: AXUIElement = AXElementReader.attribute(titleElementName, from: window),
               CFEqual(candidate, titleElement) {
                return window
            }
            current = AXElementReader.attribute(kAXParentAttribute, from: candidate)
        }
        return nil
    }
}
