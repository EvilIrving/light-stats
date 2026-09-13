//
//  AppDelegate+PanelDiagnostics.swift
//  Light Stats
//
//  Launch / popover-close journal records. Split out of AppDelegate.swift to keep
//  the lifecycle file under the file-length limit; the panel and process state it
//  reads stays owned by AppDelegate.
//

import AppKit
import Foundation

extension AppDelegate {

    func recordApplicationLaunch() {
        DiagnosticLogService.record(
            category: "application",
            action: "launched",
            fields: [
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            ]
        )
    }

    func recordPanelClosed(reason: PanelDismissReason) {
        var fields = panelDiagnosticFields()
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontmostBundleId = frontmost?.bundleIdentifier ?? "none"
        let frontmostPid = frontmost?.processIdentifier ?? -1

        fields["automatic"] = String(reason.isAutomatic)
        fields["reason"] = reason.rawValue
        fields["recentOutsideClick"] = String(isRecentOutsideClick())

        if let termination = appMemoryManager.activeTermination {
            fields["terminationInFlight"] = "true"
            fields["terminationTarget"] = termination.appName
            fields["terminationTargetBundleId"] = termination.bundleIdentifier ?? "none"
            let matchesBundle = termination.bundleIdentifier != nil && termination.bundleIdentifier == frontmostBundleId
            let matchesPid = termination.pid == frontmostPid
            fields["frontmostMatchesTerminationTarget"] = String(matchesBundle || matchesPid)
        } else {
            fields["terminationInFlight"] = "false"
        }

        fields["classification"] = classifyPanelClose(reason: reason, fields: fields)

        DiagnosticLogService.record(
            category: "popover",
            action: "closed",
            fields: fields
        )
    }

    func panelDiagnosticFields() -> [String: String] {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        return [
            "frontmostApplication": frontmostApplication?.localizedName ?? "none",
            "frontmostBundleIdentifier": frontmostApplication?.bundleIdentifier ?? "none",
            "lightStatsActive": String(NSApp.isActive),
            "panelKey": String(panel?.isKeyWindow == true),
            "panelVisible": String(panel?.isVisible == true),
            "keyWindowClass": NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none"
        ]
    }

    private func isRecentOutsideClick() -> Bool {
        guard let lastGlobalMouseDownAt else { return false }
        return Date().timeIntervalSince(lastGlobalMouseDownAt) < 0.25
    }

    /// 面板关闭归类：区分「正常」（点外部 / 手动 / 目标应用弹框置前）与「异常」（无理由失焦）。
    private func classifyPanelClose(reason: PanelDismissReason, fields: [String: String]) -> String {
        switch reason {
        case .globalMouseDown, .localMouseDown, .resignActive:
            return "externalClick"
        case .statusItemToggle, .hotkeyToggle, .externalRequest:
            return "manual"
        case .resignKey:
            if fields["terminationInFlight"] == "true" {
                return fields["frontmostMatchesTerminationTarget"] == "true"
                    ? "expectedFocusGrab"
                    : "unexpectedResign"
            }
            return fields["recentOutsideClick"] == "true" ? "externalClick" : "unexpectedResign"
        }
    }
}
