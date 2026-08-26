import AppKit

extension AppDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DiagnosticLogService.record(category: "application", action: "willTerminate")
        guard BatteryChargeControlManager.privilegedLifecycleAllowed else {
            stopRuntimeServices()
            return .terminateNow
        }
        guard !isPreparingTermination else { return .terminateLater }
        isPreparingTermination = true

        Task { @MainActor [weak self] in
            BatteryChargeControlManager.shared.prepareForTermination { success in
                guard let self else {
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
                guard success else {
                    self.isPreparingTermination = false
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
                self.stopRuntimeServices()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRuntimeServices()
    }
}
