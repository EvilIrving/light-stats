//
//  FanHardwarePolicy.swift
//  Light Stats
//
//  Machine-level fan presence. Only `noFanKeys` means the hardware is absent;
//  a failed read on a machine that has fans must keep the surfaces visible.
//

import Foundation

enum FanHardwarePolicy {

    /// Whether status bar / Overview / Monitoring settings should expose fan UI.
    ///
    /// Hidden only when the SMC probe found no fan keys at all. Every other
    /// reason — including an unresolved probe — keeps the surfaces so a
    /// temporary failure cannot look like absent hardware.
    nonisolated static func shouldShowSurfaces(reasonCode: String) -> Bool {
        reasonCode != SMCInfo.FanReason.noFanKeys
    }
}
