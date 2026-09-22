//
//  StatusBarNetworkColorStyle.swift
//  Light Stats
//
//  Status-bar network tint. System keeps the template-menu-bar colour;
//  traffic uses a fixed up/down pair so the two directions stay distinct.
//

import Foundation

enum StatusBarNetworkColorStyle: String, CaseIterable, Identifiable, Sendable {
    /// Template-tinted with the rest of the status item.
    case system
    /// Blue upload / green download — the pair from the status-bar separator request.
    case traffic

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .system: return "settings.statusBar.networkColor.system"
        case .traffic: return "settings.statusBar.networkColor.traffic"
        }
    }
}
