import AppKit

extension AppDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DiagnosticLogService.record(category: "application", action: "willTerminate")
        stopRuntimeServices()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRuntimeServices()
    }
}
