//
//  AppDelegate+AppEvents.swift
//  Light Stats
//
//  App-level notifications, split out of the delegate.
//
//  `AppDelegate` had grown to the point where its class body exceeded the project's own lint limit,
//  and the notification handlers are the least coupled thing in it: each one is a selector target
//  and nothing else, none of them touches the status item or the panel, and several of them only
//  forward to a service. A `@objc` method works exactly the same from an extension.
//

import AppKit
// `ToastCenter` takes a SwiftUI `Color`, so this file needs SwiftUI for the same reason
// `AppDelegate.swift` does — the app root is the one place allowed to reach into the View layer to
// put something on screen.
import SwiftUI

extension AppDelegate {

    /// 记录最近一次外部前台 App（用于菜单栏窗口管理）；忽略自己。
    @objc func handleApplicationActivated(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalApplicationPID = application.processIdentifier
        // The switcher's order and the preview index both change the moment another app comes
        // forward, and both are cheap to refresh here rather than inside the ⌘Tab tap.
        ApplicationActivationTracker.shared.record(processID: application.processIdentifier)
        windowPreviewIndex.invalidate()
    }

    /// Display configuration changed: drop every cached screen rectangle and re-lay the island.
    @objc func handleScreenParametersChanged() {
        ScreenGeometryProvider.invalidate()
        snapIslandController.applyGeometryChange()
    }

    @objc func handleFinderMenuActionFailed(_ notification: Notification) {
        let message = notification.userInfo?["message"] as? String ?? "findermenu.toast.actionFailed".localized
        ToastCenter.shared.show(message: message, systemImage: "exclamationmark.triangle.fill", tint: .orange, duration: 3)
    }

    /// Our own open/save sheets take the keyboard, and a Dock preview or a stolen ⌘Tab on top of one
    /// would be actively wrong.
    @objc func handleFinderMenuFilePanelWillPresent() {
        setInputSuppression(true)
    }

    @objc func handleFinderMenuFilePanelDidDismiss() {
        setInputSuppression(false)
    }

    private func setInputSuppression(_ suppressed: Bool) {
        scrollService.setSuspended(suppressed)
        titlebarGestureService.setSuspended(suppressed)
        setWindowSnapPipelineSuspended(suppressed)
        setWindowPreviewPipelineSuspended(suppressed)
    }
}
