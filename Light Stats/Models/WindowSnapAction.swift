//
//  WindowSnapAction.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import Foundation

/// Every window placement the snap engine can perform. Shared by the global shortcuts, the
/// titlebar gestures, the drag zones, and the menu bar icon.
///
/// The raw value is persisted — it is what a recorded shortcut stores and what a saved preference
/// round-trips through — so the case names are a wire format, not a style choice. Renaming a case
/// silently drops the user's binding for it.
enum WindowSnapAction: String, Codable, Sendable, Hashable, CaseIterable {
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
    case closeWindow
    case quitApplication

    /// Localization key for the settings list and the menu bar. Lives on the model because it is
    /// pure formatting; the view layer resolves it.
    ///
    /// Spelled out rather than derived from `rawValue`: the case names carry a `Half`/`Third`
    /// suffix that the existing keys do not (`window.action.left`, not `window.action.leftHalf`),
    /// and a derived key would silently resolve to an empty string instead of failing loudly.
    var titleKey: String {
        switch self {
        case .leftHalf: return "window.action.left"
        case .rightHalf: return "window.action.right"
        case .topHalf: return "window.action.top"
        case .bottomHalf: return "window.action.bottom"
        case .topLeft: return "window.action.topLeft"
        case .topRight: return "window.action.topRight"
        case .bottomLeft: return "window.action.bottomLeft"
        case .bottomRight: return "window.action.bottomRight"
        case .leftThird: return "window.action.leftThird"
        case .leftTwoThirds: return "window.action.leftTwoThirds"
        case .centerThird: return "window.action.centerThird"
        case .rightTwoThirds: return "window.action.rightTwoThirds"
        case .rightThird: return "window.action.rightThird"
        case .nextDisplay: return "window.action.nextDisplay"
        case .previousDisplay: return "window.action.previousDisplay"
        case .maximize: return "window.action.maximize"
        case .center: return "window.action.center"
        case .restore: return "window.action.restore"
        case .minimize: return "window.action.minimize"
        case .closeWindow: return "window.action.closeWindow"
        case .quitApplication: return "window.action.quitApplication"
        }
    }

    var isWindowControl: Bool { self == .closeWindow || self == .quitApplication }

    /// Actions that move a window between displays.
    var isDisplayMove: Bool {
        self == .nextDisplay || self == .previousDisplay
    }

    /// The fixed action a drag zone maps to, if any. Regions handle layouts; these cover the
    /// classic edge-and-corner vocabulary so a drag can produce the same result as a shortcut.
    static func forZone(_ zone: SnapZone) -> WindowSnapAction? {
        switch zone {
        case .left: return .leftHalf
        case .right: return .rightHalf
        case .top: return .maximize
        case .bottom: return .bottomHalf
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        case .upperHalf: return .topHalf
        case .lowerHalf: return .bottomHalf
        case .leftThird: return .leftThird
        case .leftTwoThirds: return .leftTwoThirds
        case .centerThird: return .centerThird
        case .rightTwoThirds: return .rightTwoThirds
        case .rightThird: return .rightThird
        case .none: return nil
        }
    }
}
