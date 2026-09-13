//
//  WindowSnapAction.swift
//  Light Stats
//
//  Created on 2026/09/11.
//

import Foundation

/// Every window placement the snap engine can perform. Shared by the global shortcuts, the
/// titlebar gestures, and the menu bar icon.
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
