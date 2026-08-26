import Foundation

@main
struct LightStatsBatteryHelperMain {
    @MainActor
    static func main() {
        let engine = BatteryControlEngine()
        let delegate = BatteryControlListenerDelegate(engine: engine)
        let listener = NSXPCListener(machServiceName: BatteryControlIPC.machServiceName)
        listener.delegate = delegate
        listener.setConnectionCodeSigningRequirement(BatteryControlIPC.clientCodeSigningRequirement)
        listener.resume()
        RunLoop.current.run()
    }
}
