//
//  ActivationPolicyService.swift
//  Light Stats
//

import AppKit
import OSLog

/// Switches the app between menu-bar citizen and ordinary app while one of its real windows is open.
///
/// `LSUIElement = YES` is a static declaration: without this switch no window of ours can ever be
/// reached from ⌘Tab, shown in the Dock, or brought back after something covers it — the Settings
/// window is ordinary in every way except that macOS has been told the app has no windows. Most
/// menu-bar utilities do exactly this handover, which is why opening their preferences behaves like
/// opening a preferences window anywhere else.
///
/// Installed once at launch and left running: the policy is not a preference, it is what the app is
/// at any given moment. `AppWindowPolicy` owns the decision; this type only applies it.
@MainActor
final class ActivationPolicyService {

    private let logger = AppLogger(category: "ActivationPolicy")
    private var observations: [NSObjectProtocol] = []
    private var isRegular = false

    var isRunning: Bool { !observations.isEmpty }

    func start() {
        guard observations.isEmpty else { return }
        let center = NotificationCenter.default
        // Opening a real window always makes it key or main first, and closing one is always
        // `willClose` — AppKit has no "became visible" notification, and none is needed: a window
        // that appears without becoming key is already covered by the next event to do so.
        for name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.willCloseNotification
        ] {
            observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Answered on the next turn: a window that is closing still reports itself visible
                // while its notification is being delivered, which would leave the app in the Dock
                // after the last real window had gone.
                Task { @MainActor in self?.refresh() }
            })
        }
        refresh()
    }

    private func refresh() {
        apply(regular: AppWindowPolicy.requiresRegularActivation(NSApp.windows.map(Self.describe)))
    }

    private func apply(regular: Bool) {
        guard regular != isRegular else { return }
        isRegular = regular
        NSApp.setActivationPolicy(regular ? .regular : .accessory)
        logger.info("Activation policy changed to \(regular ? "regular" : "accessory")")
        DiagnosticLogService.record(
            category: "activation",
            action: "policyChanged",
            fields: ["policy": regular ? "regular" : "accessory"]
        )
    }

    private static func describe(_ window: NSWindow) -> AppWindowPolicy.Window {
        AppWindowPolicy.Window(
            isVisible: window.isVisible,
            isMiniaturized: window.isMiniaturized,
            isNormalLevel: window.level == .normal,
            isPanel: window is NSPanel,
            isTitled: window.styleMask.contains(.titled)
        )
    }
}
