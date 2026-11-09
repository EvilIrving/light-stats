//
//  PermissionGuideDockSide.swift
//  Light Stats
//

import Foundation

/// Which side of the System Settings window the card rests on, which is also which way its arrow
/// points: the list lies towards the window, the card lies away from it.
///
/// The four sides exist because the card may not cover the window it points at — the list it is
/// asking the user to drop into and the TCC sheet that answers the drop are both inside that
/// window's rectangle, and the card is drawn above it.
nonisolated enum PermissionGuideDockSide: String, Sendable, Equatable, CaseIterable {

    /// Under the window: the list is above the card.
    case below
    /// Over the window: the list is below the card.
    case above
    /// In the gap on the window's left: the list is to the card's right.
    case left
    /// In the gap on the window's right: the list is to the card's left.
    case right

    /// Localization key of the card's one sentence, parameterised by app name and pane name.
    var instructionKey: String {
        switch self {
        case .below: return "permission.guide.instruction.above"
        case .above: return "permission.guide.instruction.below"
        case .left: return "permission.guide.instruction.beside"
        case .right: return "permission.guide.instruction.besideLeft"
        }
    }
}
