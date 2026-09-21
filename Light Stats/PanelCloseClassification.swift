//
//  PanelCloseClassification.swift
//  Light Stats
//
//  Why the popover closed, in terms a support report can aggregate.
//  `unexpectedResign` is the only interesting bucket, so it must stay rare enough
//  to mean something: a focus loss we caused ourselves is not "unexpected".
//

import Foundation

enum PanelCloseClassification: String, Sendable {
    case externalClick
    case manual
    case expectedFocusGrab
    /// 面板因为自家设置 / 关于 / 弹窗拿走 key 而关闭。
    case selfWindowTookKey
    case unexpectedResign

    static func classify(
        reason: PanelDismissReason,
        keyWindowRole: PanelKeyWindowRole,
        recentOutsideClick: Bool,
        terminationInFlight: Bool,
        frontmostMatchesTerminationTarget: Bool
    ) -> PanelCloseClassification {
        switch reason {
        case .globalMouseDown, .localMouseDown, .resignActive:
            return .externalClick
        case .statusItemToggle, .hotkeyToggle, .externalRequest:
            return .manual
        case .resignKey:
            if terminationInFlight, frontmostMatchesTerminationTarget {
                return .expectedFocusGrab
            }
            if keyWindowRole.isOwnWindow, keyWindowRole != .panel {
                return .selfWindowTookKey
            }
            if recentOutsideClick {
                return .externalClick
            }
            return .unexpectedResign
        }
    }
}
